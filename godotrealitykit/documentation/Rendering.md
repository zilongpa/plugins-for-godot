## Rendering

GodotRealityKit replaces Godot's renderer with RealityKit.

Here is a table keeping track of which rendering features are supported:

| Feature | RealityKit | Godot  |
| -- | -- | -- |
| Animated meshes | ☑️ | ☑️ |
| PBR materials | ☑️ | ☑️ |
| Shader Graphs | ☑️ | ☑️ |
| GLSL shaders | ◻ | ☑️ |
| Directional lights | ☑️ | ☑️ |
| Spotlights | ☑️ | ☑️ |
| Point lights | ☑️ | ☑️ |
| Shadowed point lights | ◻ | ☑️ |
| RealityKit portals | ☑️ | ◻ |
| visionOS hover effects | ☑️ | ◻ |

Note that some features are unique to RealityKit, in which
case GodotRealityKit exposes new nodes for them (such as [RealityPortalMeshInstance3D](./Nodes.md#realityportalmeshinstance3d)).

## Shaders

Godot's GLSL text shaders are **not** compatible with GodotRealityKit.

However, you can use Godot's Visual Shaders and they will be automatically converted
to RealityKit. Here is an example of a triplanar shader that works with GodotRealityKit:

![Godot Visual Shader graph for a triplanar mapping shader](./screenshots/TriplanarShader.png)

### GLSL remap fallback

A `ShaderMaterial` that binds a plain-text (GLSL) `Shader` cannot be rendered directly, since only
Visual Shaders are supported. To avoid a silently broken material, GodotRealityKit looks for a
sibling Visual Shader resource next to the bound shader: for a shader at `res://path/name.ext`, it
loads `res://path/name.visualshader.tres` if present. When the sibling is found and valid it is
used in place of the text shader and a warning is logged. If no sibling exists, the material is
reported as broken via an error.

This lets a project ship a text shader for Godot's own renderer alongside an equivalent
`name.visualshader.tres` for GodotRealityKit. Inline shaders authored without a resource path have no
sibling and are always reported as broken.
