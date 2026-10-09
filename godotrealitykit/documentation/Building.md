## Prerequisites

- macOS with [Xcode](https://developer.apple.com/xcode/) installed (including the visionOS SDK)
    - Use the visionOS 27 SDK
    - The Metal toolchain is required to build Godot. Install it with `xcodebuild -downloadComponent metalToolchain`.
- [SCons](https://scons.org/) build system: `python3 -m pip install scons` or `brew install scons`
- Python 3.x

## Building the Plugin

GodotRealityKit depends on custom forks of Godot and [godot-cpp](https://github.com/godotengine/godot-cpp). Their URLs and branches are configured in `deps.conf`:

```ini
# Option 1: Specify repository URLs to clone and build from source (default)
GODOT_URL=<godot git repository URL>
GODOT_BRANCH=<godot commit or branch>
GODOT_CPP_URL=<godot-cpp git repository URL>
GODOT_CPP_BRANCH=<godot-cpp commit or branch>

# Option 2: Use an existing shared workspace with pre-built deps
SHARED_WORKSPACE=../../shared_workspace
```

Running `scons` with no arguments builds everything: dependencies (if needed),
the macOS editor, visionOS device and visionOS Simulator frameworks,
documentation, and an addon containing both visionOS slices.

`SHARED_WORKSPACE` reuses prebuilt dependencies and does not check out the
commits in `deps.conf`. Before validating or packaging a build from a shared
workspace, compare both dependency HEADs to the configured commits. A
framework that compiles against other commits is not an exact-pin build.

```sh
scons
```

The addon is produced at `out/addons/GodotRealityKit/`.

To build with a release configuration:

```sh
scons config=release
```

### Individual build targets

| Command | Description |
|---|---|
| `scons deps` | Clone and build Godot + godot-cpp only |
| `scons framework platform=macos` | Build macOS framework only |
| `scons framework platform=visionos` | Build visionOS device framework only |
| `scons framework platform=visionos simulator=yes` | Build visionOS Simulator framework only |
| `scons addon` | Assemble addon for distribution |
| `scons docs` | Regenerate `doc_data.gen.cpp` from `doc_classes/*.xml` and rebuild the frameworks to embed the updated docs |

## Addon Structure

```
addons/GodotRealityKit/
    GodotRealityKit.gdextension
    plugin.cfg
    gdrk.gd
    gdrk_export.gd
    reality_ornament.gd
    Ornaments.md
    volume_camera_gizmo/
    directional_light_shadow_gizmo/
    macos.editor/                # or macos.template_release with config=release
        GodotRealityKit.framework
        godot_macos.zip
    macos.template_debug -> macos.editor
    visionos.template_debug/     # or visionos.template_release with config=release
        GodotRealityKit.xcframework/  # device and Simulator slices
        godot_visionos.zip
```

The dependency build applies the required embedded-window engine patch for
[volume ornaments](Ornaments.md). Shared prebuilt workspaces must already
contain the patched engine and rebuilt templates.

## Experimental visionOS Simulator builds

See [Simulator](Simulator.md) for Debug arm64 validation and tested limitations.
The default addon includes both device and Simulator framework slices; use its
matching Godot editor and export template when exporting an Xcode project.
