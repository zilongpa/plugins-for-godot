# GodotPhase

A GDExtension plugin that brings Apple's [PHASE](https://developer.apple.com/documentation/phase) spatial audio framework to Godot Engine.

## Apple Spatial Audio

PHASE is Apple's geometry-aware spatial audio engine for games and immersive experiences on Apple platforms, it offers:

- **Personalized Spatial Audio** — when enrolled on supported devices, PHASE delivers a spatial listening experience tuned to the user.
- **Head tracking** — on supported devices, the listener orientation follows the user's head movement.
- **Geometry-aware occlusion** — mesh-based occluders attenuate and filter sound through material presets (cardboard, glass, brick, concrete, drywall, wood).
- **Client rendering on visionOS** — mixed reality apps can render audio through the system so spatialization stays consistent with other apps sharing the user's space.

## Platform Support

| Platform | Minimum Version |
|----------|----------------|
| macOS    | 15.0+          |
| iOS      | 18.0+          |
| tvOS     | 18.0+          |
| visionOS | 26.0+          |

## Prerequisites

- macOS with Xcode
- Godot 4.5+
- [SCons](https://scons.org/) build tool (`brew install scons`)

## Building

```bash
git submodule update --init --recursive
```

```bash
# Build for macOS
./build.sh macos

# Build for other platforms
./build.sh ios
./build.sh tvos
./build.sh visionos

# Build all platforms
./build.sh all

# Clean build artifacts
./build.sh clean
```

The build output goes to `demo/bin/`.

## Installation

1. Copy the `demo/addons/GodotPhase/` folder and `demo/bin/` folder into your Godot project.
2. Enable the **GodotPhase** plugin in Project > Project Settings > Plugins.

Enabling the plugin:
- Registers the `PhaseManagerSingleton` autoload, which initializes the PHASE engine.
- Installs an export plugin that automatically attaches `PHASE.framework`, `ModelIO.framework`, `Accelerate.framework`, and `AVFoundation.framework` to iOS and visionOS exports — no manual Xcode configuration required.

## Core Components

| Node | Description |
|------|-------------|
| **PHASEManager** | Engine singleton (auto-created by plugin). Manages PHASE lifecycle, reverb presets, and the visionOS rendering mode. |
| **PHASEAudioStreamPlayer3D** | Drop-in replacement for AudioStreamPlayer3D that spatializes audio through PHASE. Supports spatial, channel, and ambient mixer types. |
| **PHASEAudioListener3D** | Defines where the player "hears from" in 3D space. Supports head tracking on compatible Apple hardware. |
| **PHASEOccluder3D** | Uses mesh geometry to block and filter audio. Assign a material preset (cardboard, glass, brick, concrete, drywall, wood) to control acoustic properties. |

For the full property and method reference for each node, see the in-engine class reference (Godot's built-in **Help** docs after enabling the plugin).

## Getting Started

### 1. Add a Listener

Add a **PHASEAudioListener3D** node as a child of your camera or player character. Every PHASE scene needs exactly one of these — it drives the per-frame listener update on the PHASE engine.

When the engine is configured to manage its own listener (the default), this node's position and rotation are synced to PHASE each physics frame. When using visionOS client rendering mode (see §5), the system supplies the listener pose and this node's transform is ignored — but the node itself is still required.

To enable head tracking on supported Apple hardware, check the **Head Tracking** property in the inspector.

### 2. Add an Audio Source

Add a **PHASEAudioStreamPlayer3D** node to any 3D object that should emit sound. Assign an `AudioStream` resource to its **Stream** property.

Choose a **Mixer Type** based on your use case:

| Mixer Type | Use Case |
|-----------|----------|
| **Spatial** (default) | Audio specifies a position and orientation in 3D space. Playback changes depending on the relative positions of the listener and source. **Required for occlusion and reverb sends.** |
| **Channel** | Maintains the channel configuration of the source audio. Also supports surround formats (5.1, 7.1, etc.).|
| **Ambient** | An audio-layering object that outputs sound in a particular direction in 3D space. |

Call `play()` or enable **Autoplay** to start playback.

### 3. Configure Reverb

The scene reverb preset is set on the **PHASEManager** singleton. PHASE provides 12 built-in presets — see the `PHASEManager` class reference for the full list. Select one in the `PhaseManagerSingleton` autoload's inspector, or set it in code:

```gdscript
PhaseManagerSingleton.set_scene_reverb_preset(PHASEManager.REVERB_PRESET_CATHEDRAL)
```

Each audio source controls how much signal is routed to the reverb via send levels:

| Property | Default | Description |
|----------|---------|-------------|
| **Direct Path Send** | 1.0 | Dry signal reaching the listener directly |
| **Early Reflections Send** | 0.2 | Signal routed to early reflections |
| **Late Reverb Send** | 0.2 | Signal routed to late reverb tail |

These sends can be toggled on/off independently with the **Enable Direct Path**, **Enable Early Reflections**, and **Enable Late Reverb** properties.

### 4. Add Occlusion (Optional)

To attenuate audio with geometry in your scene:

1. Add a **PHASEOccluder3D** node to your scene.
2. Set its **Mesh Node Path** to point at a `MeshInstance3D` whose geometry should block sound.
3. Choose a **Material** preset — this controls how the sound is attenuated and filtered when passing through.

The occluder's transform is synced to PHASE each physics frame, so it works with moving objects.

> [!NOTE]
> Occlusion only affects audio sources whose **Mixer Type** is **Spatial**.

### 5. visionOS Client Rendering Mode

On visionOS, the **Client Rendering Mode** option controls whether the PHASE engine is initialized with `PHASERenderingModeClient` (for mixed reality scenes that share spatial audio with the system, i.e. if being used with the RealityKit plugin) or `PHASERenderingModeLocal` (the app owns its own engine and listener pose). Either way, a `PHASEAudioListener3D` node must still be present in the scene — only the source of its transform changes.

This must be set before the PHASE engine initializes, so it is configured via **Project > Project Settings > phase/client_rendering_mode**. Enable **Advanced Settings** in the Project Settings dialog to see the `phase` category.

- `Automatic` (default) — `PHASERenderingModeClient` if GodotRealityKit is driving the scene, otherwise `PHASERenderingModeLocal`. Detected by checking whether the running main loop is GodotRealityKit's `RealitySceneTree`.
- `Enabled` — always `PHASERenderingModeClient`. The system supplies the listener pose; the node's transform is not applied to the engine.
- `Disabled` — always `PHASERenderingModeLocal`. The app supplies the listener pose from the `PHASEAudioListener3D` node's transform.

Call `PHASEManager.is_client_rendering_active()` to read back what the engine was actually created with.

## Demo

Open `demo/project.godot` in Godot 4.5+ and run `demo/demo.tscn` to test spatial audio playback.
