# Experimental visionOS Simulator support

The bundled RealityKit platform demo and a GLB flipbook scene have been displayed
on an Apple Silicon Mac in visionOS 27 Simulator. This is an opt-in development
path, not complete simulator support for all Godot renderers or plugin features.
The default SCons/addon export flow still builds device libraries only.

## Requirements and scope

- Xcode 27 with visionOS Simulator SDK and runtime, plus the Metal toolchain.
- A working Debug build of this plugin and its pinned Godot/godot-cpp dependencies
  following [Building](Building.md). The commands below run from `godotrealitykit/`
  and use the `deps` symlink created by the normal framework build.
- Godot commit `a191f79b9af68f3cd168687e062426578093bc8f`, as specified in `deps.conf`.
- An **isolated copy** of a Debug visionOS Xcode export. Packaging below replaces
  its plugin framework with a simulator-only framework; do not use that copy for
  device deployment or distribution.

The shared GPU code is in the external Godot dependency, not this plugin repo.
The pinned [Godot fork](https://github.com/zilongpa/godot) already includes the
simulator changes, based on rsanchezsaez/godot commit
`b2cd2726f65598d9dfdfc11242a2508551d5a629`. No manual patch is needed.
`patches/godot-visionos-simulator.patch` is retained only as a reference diff
against that upstream commit; do not apply it to the configured fork.

## Build the simulator libraries

```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
GDRK_ROOT="$PWD"
GDRK_DEPS="$(cd deps && pwd)"

test "$(git -C "$GDRK_DEPS/godot" rev-parse HEAD)" = a191f79b9af68f3cd168687e062426578093bc8f

scons -C "$GDRK_DEPS/godot" -j4 platform=visionos target=template_debug \
    simulator=yes arch=arm64 generate_bundle=no vulkan=false \
    SWIFT_FRONTEND="$GDRK_ROOT/scripts/build/swift-frontend-wrapper.sh"

scons -C "$GDRK_DEPS/godot-cpp" -j4 platform=visionos target=template_debug \
    arch=arm64 ios_simulator=yes visionos_min_version=26.0 \
    custom_api_file="$GDRK_DEPS/extension_api.json" \
    custom_tools="$GDRK_ROOT/tools" use_hot_reload=no

xcodebuild build -jobs 3 \
    -project GodotRealityKit/GodotRealityKit.xcodeproj \
    -scheme GodotRealityKit -configuration Debug \
    -sdk xrsimulator -destination 'generic/platform=visionOS Simulator' \
    -derivedDataPath "$GDRK_ROOT/out/simulator" CODE_SIGNING_ALLOWED=NO
```

If reusing a shared workspace, verify that its Godot checkout matches the pinned
commit above. An existing workspace may still contain the old upstream checkout;
update it deliberately and preserve any local edits before building.

`ios_simulator=yes` is the existing godot-cpp switch that adds `.simulator` to
object/library names. Our visionOS tool also uses it to select the **visionOS**
simulator SDK and target triple; it does not build an iOS library. Keeping the
suffix separates device and simulator outputs despite both using arm64.

## Package an isolated Xcode export

Export a project with the matching Godot editor and Debug addon first. Replace
these example paths/names with the isolated export and its existing binary name:

```sh
GDRK_EXPORT="$GDRK_ROOT/out/mygame-simulator"
GDRK_BINARY=mygame
GDRK_FRAMEWORK="$GDRK_ROOT/out/simulator/Build/Products/Debug-xrsimulator/GodotRealityKit.framework"

mkdir -p "$GDRK_EXPORT/$GDRK_BINARY.xcframework/xros-arm64-simulator"
cp "$GDRK_DEPS/godot/bin/libgodot.visionos.template_debug.arm64.simulator.a" \
    "$GDRK_EXPORT/$GDRK_BINARY.xcframework/xros-arm64-simulator/libgodot.a"
ditto "$GDRK_FRAMEWORK" \
    "$GDRK_EXPORT/$GDRK_BINARY/dylibs/addons/GodotRealityKit/visionos.template_debug/GodotRealityKit.framework"

xcodebuild build -jobs 3 \
    -project "$GDRK_EXPORT/$GDRK_BINARY.xcodeproj" -scheme "$GDRK_BINARY" \
    -configuration Debug -sdk xrsimulator \
    -destination 'generic/platform=visionOS Simulator' \
    -derivedDataPath "$GDRK_ROOT/out/simulator-app" CODE_SIGNING_ALLOWED=NO
```

The pinned export template's XCFramework Info.plist already declares
`xros-arm64-simulator`; the library directory is missing until this packaging
step. Verify that declaration if using another export template. Do not rename a
device binary to make it appear to be a simulator binary.

## Enable the experimental runtime path

Set `GDRK_SIMULATOR_SKIP_GPU_CHECK=1` in the exported Xcode scheme's **Run →
Arguments → Environment Variables**, then select an Apple Vision Pro Simulator
and run. The flag is read only in `VISIONOS_SIMULATOR` builds; it leaves the
device capability flags and the physical-device check unchanged.

Alternatively, install to a booted simulator and launch with `simctl` (replace
the UUID and the bundle ID with those from your simulator/export):

```sh
GDRK_SIMULATOR_UUID='<booted simulator UUID>'
GDRK_BUNDLE_ID='<exported application bundle ID>'
xcrun simctl install "$GDRK_SIMULATOR_UUID" \
    "$GDRK_ROOT/out/simulator-app/Build/Products/Debug-xrsimulator/$GDRK_BINARY.app"
SIMCTL_CHILD_GDRK_SIMULATOR_SKIP_GPU_CHECK=1 xcrun simctl launch \
    --terminate-running-process "$GDRK_SIMULATOR_UUID" "$GDRK_BUNDLE_ID"
```

Launching from the simulator home screen does not necessarily preserve this
environment variable. Use Xcode or the explicit `simctl` launch command.

## What changed and why

| Location | Change |
| --- | --- |
| `tools/visionos.py` | Select simulator SDK/target and honor minimum OS version; keep separate godot-cpp output names. |
| `GodotRealityKit/Configurations/Config.xcconfig` | Accept `xrsimulator` and link matching Debug/Release simulator godot-cpp libraries. |
| `scripts/build/swift-frontend-wrapper.sh` | Find simulator SwiftUI host macros in the corresponding XROS device platform. |
| `scripts/build/generate-default-metallib.sh` | Compile the Metal library for the framework's platform rather than always macOS. |
| Engine: `platform/visionos/detect.py` | Keep requested Metal support enabled for simulator builds; XR and plugin code depend on it. |
| Engine: `thirdparty/metal-cpp/metal_cpp.cpp` | Use metal-cpp's runtime lookup for optional constants absent from the simulator SDK. |
| Engine: `drivers/metal/rendering_device_driver_metal.cpp` | Allow an explicit simulator-only bypass of the Apple4 minimum-family check. |
| Engine: `drivers/metal/rendering_context_driver_metal.cpp` | Use ordinary `presentDrawable`, since `MTLSimCommandBuffer` does not implement the minimum-duration variant. |

The GPU-family check rejected the scene before it could start. Bypassing it
initially exposed an `unrecognized selector` crash for
`presentDrawable:afterMinimumDuration:`. With that simulator API fallback, the
platform demo displayed its floor, stairs and character, and the GLB test loaded
48 meshes and cycled 16 timesteps. After warmup, application counters reported
about 60 loop/frame-switch updates per second; this is not an independent GPU
presentation-rate measurement.

These scene tests used Xcode 27.0 (27A266a), visionOS SDK/runtime 27.0 and Debug
arm64 builds. The original GLB experiment also contained unrelated local plugin changes.
The scoped framework from this fork was then independently rebuilt and packaged
with the bundled platform demo; its floor, stairs and character were confirmed
visible in Simulator without those unrelated changes. Hand/controller tracking, all materials/shadows, Release builds and
physical-device regressions are not covered. Missing simulator GPU capabilities
remain missing: this opt-in must not be interpreted as general Metal support.

See Apple's [Metal simulator limitations](https://developer.apple.com/documentation/metal/developing-metal-apps-that-run-in-simulator)
and the [Metal feature tables](https://developer.apple.com/metal/Metal-Feature-Set-Tables.pdf).
