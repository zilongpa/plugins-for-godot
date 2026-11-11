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

#if !os(macOS)

import ARKit
import RealityKit

/// Tracks the person's hands in the immersive space, the only place visionOS lets ARKit track
/// them, and publishes each hand's joints to the engine's hand trackers (see
/// GDRKBridgeDelegate::setHandJoint). The immersive view holds one.
@MainActor
final class HandAnchors {
    private let session = ARKitSession()
    private let provider = HandTrackingProvider()
    private var started = false

    /// ARKit's joints, each with the XRHandTracker.HandJoint it stands for. ARKit has no palm
    /// joint: the palm is taken halfway along the middle finger's metacarpal.
    private static let joints: [(HandSkeleton.JointName, Int32)] = [
        (.wrist, 1),
        (.thumbKnuckle, 2), (.thumbIntermediateBase, 3), (.thumbIntermediateTip, 4), (.thumbTip, 5),
        (.indexFingerMetacarpal, 6), (.indexFingerKnuckle, 7), (.indexFingerIntermediateBase, 8),
        (.indexFingerIntermediateTip, 9), (.indexFingerTip, 10),
        (.middleFingerMetacarpal, 11), (.middleFingerKnuckle, 12), (.middleFingerIntermediateBase, 13),
        (.middleFingerIntermediateTip, 14), (.middleFingerTip, 15),
        (.ringFingerMetacarpal, 16), (.ringFingerKnuckle, 17), (.ringFingerIntermediateBase, 18),
        (.ringFingerIntermediateTip, 19), (.ringFingerTip, 20),
        (.littleFingerMetacarpal, 21), (.littleFingerKnuckle, 22), (.littleFingerIntermediateBase, 23),
        (.littleFingerIntermediateTip, 24), (.littleFingerTip, 25),
    ]
    private static let palm: Int32 = 0

    /// Starts tracking when wanted and pushes both hands' joints, relative to `root`. Call once
    /// per scene update.
    func update(root: RealityKit.Entity, delegate: GDRKBridgeDelegate?) {
        guard let delegate, delegate.wantsHandTracking(), HandTrackingProvider.isSupported else { return }
        startIfNeeded()
        guard provider.state == .running else { return }

        let rootFromOrigin = root.transformMatrix(relativeTo: nil).inverse
        let latest = provider.latestAnchors
        publish(latest.leftHand, as: .leftHand, rootFromOrigin: rootFromOrigin, delegate: delegate)
        publish(latest.rightHand, as: .rightHand, rootFromOrigin: rootFromOrigin, delegate: delegate)
    }

    private func publish(_ anchor: HandAnchor?, as hand: ControllerHand, rootFromOrigin: simd_float4x4, delegate: GDRKBridgeDelegate) {
        guard let anchor, anchor.isTracked, let skeleton = anchor.handSkeleton else {
            delegate.setHandTracked(hand, false)
            return
        }
        let rootFromAnchor = rootFromOrigin * anchor.originFromAnchorTransform
        func rootFromJoint(_ name: HandSkeleton.JointName) -> simd_float4x4 {
            rootFromAnchor * skeleton.joint(name).anchorFromJointTransform
        }

        for (name, joint) in Self.joints {
            delegate.setHandJoint(hand, joint, Self.transform(rootFromJoint(name)))
        }
        var palm = rootFromJoint(.middleFingerKnuckle)
        palm.columns.3 = (rootFromJoint(.middleFingerMetacarpal).columns.3 + palm.columns.3) * 0.5
        delegate.setHandJoint(hand, Self.palm, Self.transform(palm))
        delegate.setHandTracked(hand, true)
    }

    private static func transform(_ matrix: simd_float4x4) -> GDRKTransform {
        let t = Transform(matrix: matrix)
        return GDRKTransform(scale: t.scale, position: t.translation, orientation: t.rotation)
    }

    private func startIfNeeded() {
        guard !started else { return }
        started = true
        Task { @MainActor in
            do {
                try await self.session.run([self.provider])
                NSLog("[GDRK] hand tracking started")
            } catch {
                NSLog("[GDRK] hand tracking unavailable: \(error)")
            }
        }
    }
}

#endif
