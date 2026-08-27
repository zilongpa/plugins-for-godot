# Changelog

## [1.1.0] - 2026-08-27

### Added
- Experimental `RealityClipping3D` node wrapping RealityKit's
  `ClippingComponent`, with an editor gizmo, to clip a subtree to a box with
  optional feathered edges.

### Documentation
- Documented the macOS RealityKit preview mode, including the Godot editor
  setting that must be disabled so the running game isn't embedded in the
  editor.
- `Building.md` now recommends the visionOS 27 SDK instead of visionOS 26.

### Refactors
- Split each node loader's monolithic `update()` into four phases
  (`update_transforms`, `update_dirty_flags`, `update_visibility_states`,
  `update_deps_usage`) orchestrated by `SceneLoader::update()`, and added
  `used_in_frame` tracking infrastructure to `ResourceLoader<>`. Gives per-frame
  optimizations a consistent place to skip unchanged work instead of each loader
  inventing its own dirty-tracking.
- Consolidated per-surface AABB computation into a single
  `MeshLoader::get_aabb()` call instead of querying `find_mesh` once per
  surface, cutting redundant lookups on meshes with many surfaces, and fixed
  missing "used in frame" marking on material textures.

### Performance
- Reduced deformation update cost, which was taking 25% of total plugin frame
  time, by reusing deform matrices across surfaces and caching bone inverse
  transforms instead of round-tripping to Godot every frame.
- MultiMesh instances now dematerialize their RealityKit entities when they stop
  contributing to the scene, instead of keeping them materialized and paying for
  entities that no longer render anything.
- Materials use default emission/albedo parameters when possible, so channels a
  material doesn't actually customize take RealityKit's cheap built-in path
  instead of a full shader graph evaluation.
- Fixed RealityKit rendering inefficiency caused by having SGL materials output
  a default vertex-position-offset parameter when no clipping is needed,
  avoiding an unnecessary second render pass for meshes that never move their
  vertices.
- Split mesh attribute (color/UV) encoding from position encoding, so animated
  (skinned/blend-shaped) meshes no longer re-upload unchanged color/UV data
  every frame just because positions are dirty.
- Mesh surfaces are now compacted into a single RealityKit `MeshResource` when
  possible, replacing a separate `Mesh::compacted` flag with a derived
  `compacted_resource` state, cutting the number of RealityKit resources a
  multi-surface mesh needs to create.

### Fixed
- Crash on background/foreground relaunch in immersive apps, caused by the
  engine re-running its setup and double-registering singletons.
- Crash after remaining idle for an extended period, caused by reentrant calls
  into the nested Godot view recursing the display link.
- Incorrect XROrigin scale relative to Compositor Services, caused by the bridge
  double-applying the world scale.
- Incorrect XROrigin translation relative to Compositor Services.
- Directional lights had incorrect intensity.
- Vertex colors lost their alpha channel; the vertex-color path now carries full
  RGBA.
- Possible crash when a MultiMesh isn't a valid instance.
- `MeshInstanceLoader` never showing a node that started invisible outside the
  volumetric window.
- Various log spam fixes.

### Fixed (Hand/Controller Tracking)
> These fixes only matter if you cherry-pick hand- and controller-tracking
> support into your own Godot engine checkout — this is not an officially
> supported workflow.

- Crash on visionOS caused by a missing privacy usage key in the exported
  `Info.plist` when RealityKit implicitly starts an ARKit session for spatial
  gestures.
- PSVR2 anchor failing to reappear after backgrounding and reconnecting a
  controller in windowed mode.
- PSVR2 tracking/anchoring failing in immersive space.
- PSVR2 anchoring using the wrong transform/offset in shared space and windowed
  apps.
- Hand tracking (anchor and joints) failing.
- Mismatched visionOS project settings preventing the hand- and controller-
  tracking privacy usage keys from being emitted in the exported `Info.plist`,
  which otherwise crashes the app when it requests hand/controller-tracking
  authorization.
