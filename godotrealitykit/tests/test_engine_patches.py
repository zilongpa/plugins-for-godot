"""Exercise the real integration patch against the pinned engine's source files."""
import importlib.util
import os
from pathlib import Path
import re
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
PATCH = ROOT / "patches/godot-ornament-hosting.patch"
SPEC = importlib.util.spec_from_file_location(
    "engine_patches", ROOT / "scripts/build/apply-engine-patches.py")
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class EnginePatchTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        engine = Path(os.environ.get("GDRK_TEST_ENGINE", ROOT / "deps/godot"))
        if not (engine / ".git").exists():
            raise unittest.SkipTest("Set GDRK_TEST_ENGINE to a checkout containing the pinned engine commit")
        pin = re.search(r"^GODOT_BRANCH=(.+)$", (ROOT / "deps.conf").read_text(), re.M)[1]
        cls.original = {
            name: subprocess.check_output(["git", "show", f"{pin}:{name}"], cwd=engine)
            for name in re.findall(r"^--- a/(.+)$", PATCH.read_text(), re.M)
        }

    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="ornament-patch-test-")
        self.addCleanup(self.temporary.cleanup)
        self.engine = Path(self.temporary.name)
        for name, contents in self.original.items():
            target = self.engine / name
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(contents)

    def snapshot(self):
        return {p.relative_to(self.engine): p.read_bytes()
                for p in self.engine.rglob("*") if p.is_file()}

    def test_applies_once_and_preserves_unrelated_work(self):
        note = b"\n// Unrelated local engine change.\n"
        for name in self.original:
            with (self.engine / name).open("ab") as stream:
                stream.write(note)
        MODULE.apply_patch(self.engine, PATCH)
        patched = self.snapshot()
        for name, original in self.original.items():
            contents = patched[Path(name)]
            self.assertNotEqual(contents, original + note)
            self.assertTrue(contents.endswith(note))
            self.assertIn(b"godotEmbeddedWindow", contents)
        MODULE.apply_patch(self.engine, PATCH)
        self.assertEqual(patched, self.snapshot())

    def test_conflict_does_not_partially_patch_other_files(self):
        # Conflict in the last file, after earlier files could otherwise apply.
        controller = self.engine / "drivers/apple_embedded/godot_view_controller.mm"
        contents = controller.read_bytes()
        self.assertIn(b"- (void)viewDidDisappear:(BOOL)animated {", contents)
        controller.write_bytes(contents.replace(
            b"- (void)viewDidDisappear:(BOOL)animated {",
            b"- (void)viewDidDisappear:(BOOL)isAnimated {"))
        before = self.snapshot()
        with self.assertRaises(RuntimeError):
            MODULE.apply_patch(self.engine, PATCH)
        self.assertEqual(before, self.snapshot())

    def test_partially_applied_patch_is_rejected_without_changes(self):
        MODULE.apply_patch(self.engine, PATCH)
        header = "drivers/apple_embedded/godot_view_controller.h"
        (self.engine / header).write_bytes(self.original[header])
        before = self.snapshot()
        with self.assertRaises(RuntimeError):
            MODULE.apply_patch(self.engine, PATCH)
        self.assertEqual(before, self.snapshot())


if __name__ == "__main__":
    unittest.main()
