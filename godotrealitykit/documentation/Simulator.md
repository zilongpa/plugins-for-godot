# Experimental visionOS Simulator support

The bundled RealityKit platform demo and a GLB flipbook scene have been displayed
on an Apple Silicon Mac in visionOS 27 Simulator. This is an experimental development
path, not complete simulator support for all Godot renderers or plugin features.
The default SCons/addon build packages both device and Simulator libraries.

## Requirements and scope

- Xcode 27 with visionOS Simulator SDK and runtime, plus the Metal toolchain.
- A working Debug build of this plugin and its pinned Godot/godot-cpp dependencies
  following [Building](Building.md). Run the commands below from `godotrealitykit/`.
- The exact Godot and godot-cpp commits specified in `deps.conf`.
- A Debug visionOS Xcode export made with the matching editor, addon and template.

The shared GPU code is in the external Godot dependency, not this plugin repo.
The pinned [Godot fork](https://github.com/zilongpa/godot) already includes the
simulator changes, based on rsanchezsaez/godot commit
`b2cd2726f65598d9dfdfc11242a2508551d5a629`. No manual patch is needed.
`patches/godot-visionos-simulator.patch` is retained only as a reference diff
against that upstream commit; do not apply it to the configured fork.

## Build and export

```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
scons -j4 config=debug
test "$(git -C deps/godot rev-parse HEAD)" = "$(sed -n 's/^GODOT_BRANCH=//p' deps.conf)"
test "$(git -C deps/godot-cpp rev-parse HEAD)" = "$(sed -n 's/^GODOT_CPP_BRANCH=//p' deps.conf)"
```

The addon is at `out/addons/GodotRealityKit/`. Its
`visionos.template_debug/GodotRealityKit.xcframework` contains both
`xros-arm64` and `xros-arm64-simulator`; the same directory contains the
matching `godot_visionos.zip` export template. Export with the matching editor
at `deps/godot/bin/godot.macos.editor.dev.arm64`.

`ios_simulator=yes` is the existing godot-cpp switch that adds `.simulator` to
object/library names. Our visionOS tool also uses it to select the **visionOS**
simulator SDK and target triple; it does not build an iOS library. Keeping the
suffix separates device and simulator outputs despite both using arm64.
The export uses the matching engine template's Simulator slice and embeds the
plugin XCFramework. No manual library replacement is needed.

## Run the simulator build

Select an Apple Vision Pro Simulator in the exported Xcode project and run.
The pinned engine automatically skips the Apple4 startup gate, unsupported depth
clip mode calls, and residency sets when compiled with `VISIONOS_SIMULATOR`.
No launch environment variable is required, including when launching from the
simulator home screen. Physical-device behavior is unchanged.

Depth clamping remains unavailable: the simulator keeps its default clipping
behavior. These compatibility defaults do not add missing GPU features.

## What changed and why

| Location | Change |
| --- | --- |
| `tools/visionos.py` | Select simulator SDK/target and honor minimum OS version; keep separate godot-cpp output names. |
| `GodotRealityKit/Configurations/Config.xcconfig` | Accept `xrsimulator` and link matching Debug/Release simulator godot-cpp libraries. |
| `scripts/build/swift-frontend-wrapper.sh` | Find simulator SwiftUI host macros in the corresponding XROS device platform. |
| `scripts/build/generate-default-metallib.sh` | Compile the Metal library for the framework's platform rather than always macOS. |
| Engine: `drivers/metal/metal_objects_shared.h` | Omit unsupported depth clip mode calls in simulator builds. |
| Engine: `drivers/metal/metal_device_properties.cpp` | Disable residency sets for simulator builds; queue setup honors this capability. |
| Engine: `platform/visionos/detect.py` | Keep requested Metal support enabled for simulator builds; XR and plugin code depend on it. |
| Engine: `thirdparty/metal-cpp/metal_cpp.cpp` | Use metal-cpp's runtime lookup for optional constants absent from the simulator SDK. |
| Engine: `drivers/metal/rendering_device_driver_metal.cpp` | Skip the Apple4 minimum-family check by default only for simulator builds. |
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
remain missing: these defaults must not be interpreted as general Metal support.

See Apple's [Metal simulator limitations](https://developer.apple.com/documentation/metal/developing-metal-apps-that-run-in-simulator)
and the [Metal feature tables](https://developer.apple.com/metal/Metal-Feature-Set-Tables.pdf).

The default-compatibility engine was also checked with Wiz on visionOS 27
Simulator: no GPU override environment variable, Metal API validation enabled,
and the sample cube/platform visibly rendered. This does not certify other scenes.
