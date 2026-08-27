# Changelog

## [1.1.0] - 2026-06-10

### Changed
- Renamed plugin from `phasegodot` to `godotphase`.
- Replaced the `phase/use_client_rendering_mode` boolean project setting with
  the `phase/client_rendering_mode` enum.
- Audio session reactivation after an interruption or a return to the foreground
  now retries asynchronously with backoff instead of a single attempt whose
  failure was discarded.

### Added
- `phase/client_rendering_mode` project setting with `Automatic`, `Enabled`, and
  `Disabled` modes. `Automatic` selects `PHASERenderingModeClient` when
  GodotRealityKit is driving the scene.
- `registerAudioAssetWithURL:` to `PHASEEngineWrapper`.
- Mono channel support in `PHASEWrapperRingBuffer` write path.
- `consumeAndResetUnderrunCount` on `PHASEWrapperRingBuffer`.

### Fixed
- `framesToWrite` count passed to `vDSP_ctoz` in `PHASEWrapperRingBuffer`.
- Stereo input pointer arithmetic in `PHASEWrapperRingBuffer write:`
  now uses the correct interleaved-stereo offset.
- Corrected typos in developer comments in PHASEWrapper

### Removed
- Unused `MixerType` enum from `PHASEWrapper.h`.

## [1.0.0] - 2026-06-08
