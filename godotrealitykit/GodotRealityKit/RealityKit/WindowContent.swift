//===----------------------------------------------------------------------===//
// Copyright © 2026 GodotRealityKit contributors.
//
// Licensed under the MIT license (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
// LICENSE
//
//===----------------------------------------------------------------------===//

#if os(visionOS)

import RealityKit
import SwiftUI

/// The content of a Godot Window that opens as a volume or a portal window.
/// The engine presents it in its own window scene; see WindowHosts.
public enum WindowContent {
    /// A volume showing `root`, sized in meters. Zero components of the
    /// minimum and maximum leave them unbounded. Returns a retained AnyView.
    public static func makeVolume(root: Entity, delegate: GDRKBridgeDelegate, size: GDRKVolumeSize) -> UnsafeMutableRawPointer {
        let frame = VolumeFrame(size: size.size, minSize: size.minimum, maxSize: size.maximum, resizable: size.resizable)
        return assumeMainActor(root, delegate, frame) { root, delegate, frame in
            let view = AnyView(SharedVolumetricRealityView(root: root.value, delegate: delegate)
                .modifier(VolumeMeasurement(delegate: delegate))
                .modifier(frame))
            return Unmanaged.passRetained(view as AnyObject).toOpaque()
        }
    }

    /// A portal window looking into `root`. Returns a retained AnyView.
    public static func makePortal(root: Entity, delegate: GDRKBridgeDelegate) -> UnsafeMutableRawPointer {
        assumeMainActor(root, delegate) { root, delegate in
            let view = AnyView(PortalRealityView(root: root.value, delegate: delegate))
            return Unmanaged.passRetained(view as AnyObject).toOpaque()
        }
    }
}

/// Reports the volume's size in meters as the person resizes it.
private struct VolumeMeasurement: ViewModifier {
    let delegate: GDRKBridgeDelegate

    @Environment(\.physicalMetrics) private var metrics

    func body(content: Content) -> some View {
        GeometryReader3D { proxy in
            content.onChange(of: proxy.size, initial: true) { _, size in
                delegate.onVolumeMeasured(simd_float3(
                    Float(metrics.convert(size.width, to: .meters)),
                    Float(metrics.convert(size.height, to: .meters)),
                    Float(metrics.convert(size.depth, to: .meters))))
            }
        }
    }
}

/// Sizes a volume's content; the window's size follows its content.
private struct VolumeFrame: ViewModifier {
    let size: simd_float3
    let minSize: simd_float3
    let maxSize: simd_float3
    let resizable: Bool

    @Environment(\.physicalMetrics) private var metrics

    func body(content: Content) -> some View {
        let ideal = points(size, unbounded: 0)
        let lower = resizable ? points(minSize, unbounded: 0) : ideal
        let upper = resizable ? points(maxSize, unbounded: .infinity) : ideal
        content
            .frame(minWidth: lower.x, idealWidth: ideal.x, maxWidth: upper.x,
                   minHeight: lower.y, idealHeight: ideal.y, maxHeight: upper.y)
            .frame(minDepth: lower.z, idealDepth: ideal.z, maxDepth: upper.z)
    }

    private struct Points {
        let x: CGFloat
        let y: CGFloat
        let z: CGFloat
    }

    private func points(_ meters: simd_float3, unbounded: CGFloat) -> Points {
        func convert(_ value: Float) -> CGFloat {
            value > 0 ? metrics.convert(CGFloat(value), from: .meters) : unbounded
        }
        return Points(x: convert(meters.x), y: convert(meters.y), z: convert(meters.z))
    }
}

#endif
