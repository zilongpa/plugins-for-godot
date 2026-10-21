## Troubleshooting

### Build for a physical Apple Vision Pro instead of the simulator

GodotRealityKit does not currently work on the visionOS simulator. It requires
a physical Apple Vision Pro device.

Xcode shows the following compilation error if you try to build for the visionOS simulator:

```
The folder "xros-arm64-simulator" doesn't exist.
```

### Match the Debug and Release export templates

If you only set up the Debug export template but export in Release, Xcode shows the following compilation error:

```
The folder "xros-arm64" doesn't exist.
```

The same error occurs if you only set up the Release export template but export in Debug.

To resolve, do one of the following:
1. Build both the Debug and Release versions of the export template.
2. Export with the matching Debug or Release checkbox.
