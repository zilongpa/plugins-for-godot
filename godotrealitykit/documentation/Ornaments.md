# Godot controls in volume ornaments

`RealityOrnament` hosts existing Godot `Control` nodes in a system visionOS ornament attached to a RealityKit volume. Buttons, sliders, themes, signals, and GDScript continue to run in Godot. SwiftUI supplies the native host, glass background, and viewpoint transitions.

## Add a panel

1. Build GodotRealityKit with its matching patched engine and copy the generated `addons/GodotRealityKit` into your project. For native hover highlights, also install the separate `addons/GodotVisionOS` addon.
2. Add a `RealityOrnament` node, or attach `res://addons/GodotRealityKit/reality_ornament.gd` to a `Window`.
3. Add a full-rect `Control` or container under it, then add your controls. Leave `Visible` off in the saved scene; `Show On Ready` opens the panel after setup.
4. For the main volume, leave `Volume ID` at `0`. For a volume created at runtime, disable `Show On Ready`, then attach it after creating the volume:

```gdscript
var volume_id = get_tree().open_volume_window("res://model.tscn", "Model")
var result = $RealityOrnament.attach_to_volume(volume_id)
if result != OK:
    push_error("Unable to attach ornament: %s" % error_string(result))
```

The project must use `RealitySceneTree`. Volume IDs are distinct from `DisplayServer` window IDs. A target volume must exist, but its native scene may still be opening. Enable `input_devices/pointing/emulate_mouse_from_touch` for controls such as sliders that consume mouse events.

## Properties

| Setting | Meaning |
| --- | --- |
| `volume_id` | Owning volume; `0` is the main volumetric scene. To change ownership at runtime, call `attach_to_volume(id)`. |
| `panel_size` | Logical layout size in native points; default `480 × 260`. Godot content scales to the corresponding pixel dimensions. Changing it resizes the panel without resizing the volume. |
| `hover_enabled` | Adds the existing GodotVisionOS `VisionOSHoverRoot2D` for native gaze highlights. Default `true`. |
| `show_on_ready` | Opens after scene-tree setup. Disable when the target volume will be created later. |

The first version supports **one panel per volume**, including multiple independent volumes. Put related controls inside a single panel. A second panel targeting the same volume is rejected without closing the original. Invalid or missing volume IDs return an error before hiding the existing panel. Native presentation failures use the plugin's existing window-failure path.

Call `hide()` to remove a panel and `attach_to_volume(id)` to show or reattach it. Its Godot child controls retain their state. Closing the volume removes the native view while preserving the logical panel; reopening the volume restores it. Destroying the volume hides its panel. On other platforms, the same controls open in an ordinary Godot window.

`is_native_visible()` reports whether the logical panel is visible and its native content is presented. It does not detect compositor occlusion or temporary fading during a system drag. On desktop it reports ordinary window visibility.

## Placement and appearance

The panel attaches near the volume's bottom-front edge, with its scene anchor moved outward to leave room for the tilted panel. Clearance is calculated from half the panel diagonal plus 24 layout points, converted to physical distance in the ornament's environment. The smaller horizontal extent of the volume converts that distance into an anchor beyond its front boundary, allowing the same rule to follow side viewpoints and respond to resizing.

The host moves the attachment itself rather than offsetting pixels outside the ornament's measured bounds. This avoids the cropping caused by moving the embedded view past its own layout bounds. It also reduces overlap with the volume's 3D contents. Placement is automatic; there are no manual above/below-handle, rotation, or custom-anchor controls.

visionOS owns the ornament's orientation, perceived scale, and face-change animation. A fixed `panel_size` specifies layout points, not a constant physical or apparent size at every viewing distance. No custom camera rotation, angle compensation, spatial-input forwarding, or face-transition animation is applied.

The helper embeds popup subwindows inside the panel. A popup does not enlarge the ornament automatically, so allow room for it or use the main app window for larger dialogs.

## Native hover

Hover uses `GodotVisionOS`, including its control discovery, clipping, occlusion, and popup handling. `RealityOrnament` creates a `VisionOSHoverRoot2D`; it does not supply a separate hover renderer. Existing `UIKitHoverEffect2D` and `VisionOSHoverStyle2D` overrides remain available. Disable `hover_enabled` if you already manage a hover root for the same controls.

Without GodotVisionOS, the panel remains usable and logs a warning on visionOS. `get_native_hover_target_count()` exposes the hover root's registered target count for diagnostics. Native gaze highlighting does not synthesize Godot mouse-hover events or automatically apply a Godot theme's hover style.

## Build requirements

The integration requires `patches/godot-ornament-hosting.patch`, against the engine revision in `deps.conf`. The normal dependency build applies it automatically. The patch makes window resizing, titles, and detachment local to the embedded controller, preserving the parent volume and logical Godot UI state.

For a separately managed engine checkout:

```sh
python3 scripts/build/apply-engine-patches.py /path/to/godot
```

Rebuild the engine export template as well as the plugin. When updating a checkout with existing dependencies, run `scons deps` before rebuilding the addon; the default build can reuse already-present dependency binaries. The patch helper recognizes an already-patched tree, preserves unrelated engine changes, and stops before applying a conflicting patch. The plugin refuses to open ornaments when the running engine lacks embedded-window support.

`SHARED_WORKSPACE` reuses prebuilt dependencies: it does not patch or rebuild the engine. Supply a rebuilt editor and export template when using it. The plugin's existing visionOS 26 minimum and visionOS 27 SDK requirement also apply to ornaments. See [Building](Building.md).

GodotVisionOS is built separately; building GodotRealityKit does not implicitly build that addon.

## Verification

`tests/ornaments` is a standalone project with playback controls, a rotating model, and panel/volume lifecycle actions. Copy both built addons into its `addons` directory and export the `visionOS` preset using the matching editor. Build and run the generated Xcode project for a device or simulator.

Launch with `-- --automated` to run the regression checks. Results appear as `ORNAMENT_CHECK` and `ORNAMENT_RESULT` in the log and in `user://ornament-results.json`. Checks cover presentation, invalid targets, duplicate rejection, panel resizing without resizing the volume, preserved UI state, multiple volumes, destruction, and hover registration. The temporary resize is restored to the demo's original `520 × 220` points.

Input checks inject pixel-space touch and drag events through Godot's `Input` and `DisplayServer`, including touch-to-mouse emulation. They verify Godot routing, not actual UIKit gaze/pinch interaction. On Vision Pro, additionally check selection, continuous slider dragging, popups, viewpoint transitions, system-handle dragging, and repeated close/reopen cycles.

The current simulator validation shows a complete panel in front and side views with outward clearance. This does not certify every intermediate compositor pose. A panel may temporarily disappear while its volume is dragged and return on release; the cause of that observed behavior remains unresolved. Native lifecycle logs distinguish presentation changes from controller detachment. Real headset gaze/pinch and hover appearance remain manual checks.

To test engine patch application, idempotency, and conflict preservation against a local checkout containing the pinned engine commit:

```sh
GDRK_TEST_ENGINE=/path/to/godot python3 -m unittest discover -s tests -p 'test_*.py'
```
