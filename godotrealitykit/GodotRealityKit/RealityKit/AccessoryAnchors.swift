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

@preconcurrency import GameController
import RealityKit
import SwiftUI

/// Anchors the spatial controllers in one RealityView and pushes their poses and input to the
/// engine's accessory controller interface. A volume or portal holds one; it only anchors while
/// its delegate wants controller anchors (see GDRKBridgeDelegate::wantsControllerAnchors).
@MainActor
final class AccessoryAnchors {
    /// Holds the accessory anchors. Add it to the RealityView's content once, in make.
    let container = RealityKit.Entity()

    private struct Anchors {
        let grip: AnchorEntity
        let aim: AnchorEntity?
    }

    // One accessory tracking session serves every view.
    private static var session: SpatialTrackingSession? = nil
    private static var sessionStarted = false

    private var started = false
    nonisolated(unsafe) private var connectObserver: NSObjectProtocol? = nil
    private var pendingControllers: [GCController] = []
    // An AnchorEntity(.accessory) resolves asynchronously; resolved anchors wait here until the
    // next scene update adds them to the container.
    private var resolvedAnchors: [ControllerHand: Anchors] = [:]
    private var anchors: [ControllerHand: Anchors] = [:]
    // The GCController anchored per hand, polled each frame for button / thumbstick input.
    private var controllers: [ControllerHand: GCController] = [:]

    deinit {
        if let observer = connectObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    private func install() {
        for (hand, resolved) in resolvedAnchors {
            // Each connect gives the controller a new accessory identity, so the newest resolved
            // anchor replaces what is installed; the one it replaces can no longer track.
            if let stale = anchors[hand] {
                stale.grip.removeFromParent()
                stale.aim?.removeFromParent()
            }
            container.addChild(resolved.grip)
            if let aim = resolved.aim {
                container.addChild(aim)
            }
            anchors[hand] = resolved
        }
        resolvedAnchors.removeAll()
    }

    /// Starts tracking when wanted and pushes poses relative to `root` and input. Call once per
    /// scene update.
    func update(root: RealityKit.Entity, delegate: GDRKBridgeDelegate?) {
        guard let delegate, delegate.wantsControllerAnchors() else { return }

        startIfNeeded()
        resolvePendingControllers()
        install()

        for (hand, anchor) in anchors {
            delegate.setControllerAnchor(hand, Self.transform(of: anchor.grip, relativeTo: root), anchor.grip.isAnchored)
            if let aim = anchor.aim {
                delegate.setControllerAim(hand, Self.transform(of: aim, relativeTo: root), aim.isAnchored)
            }
        }
        // The engine samples each controller's buttons / thumbstick (via GameController), so
        // XRController3D's button_pressed keeps working.
        for (hand, controller) in controllers {
            delegate.setControllerInput(hand, Unmanaged.passUnretained(controller).toOpaque())
        }
    }

    private static func transform(of anchor: RealityKit.Entity, relativeTo root: RealityKit.Entity) -> GDRKTransform {
        let t = Transform(matrix: anchor.transformMatrix(relativeTo: root))
        return GDRKTransform(scale: t.scale, position: t.translation, orientation: t.rotation)
    }

    // Starts the accessory tracking session and queues the spatial controllers for anchoring;
    // an AnchorEntity(.accessory) only resolves once a live session is running.
    private func startIfNeeded() {
        guard !started else { return }
        started = true
        NSLog("[GDRK] accessory anchoring started; \(GCController.controllers().count) controller(s) connected")

        if !Self.sessionStarted {
            Self.sessionStarted = true
            Task { @MainActor in
                let session = SpatialTrackingSession()
                let unavailable = await session.run(SpatialTrackingSession.Configuration(tracking: [.accessory]))
                if let unavailable {
                    NSLog("[GDRK] accessory tracking unavailable: \(unavailable)")
                }
                Self.session = session
            }
        }

        connectObserver = NotificationCenter.default.addObserver(
            forName: NSNotification.Name.GCControllerDidConnect,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let controller = notification.object as? GCController else { return }
            MainActor.assumeIsolated { Self.logController(controller) }
            guard controller.productCategory == GCProductCategorySpatialController else { return }
            MainActor.assumeIsolated {
                self?.pendingControllers.append(controller)
            }
        }

        for controller in GCController.controllers() {
            Self.logController(controller)
            if controller.productCategory == GCProductCategorySpatialController {
                pendingControllers.append(controller)
            }
        }
    }

    // Probe logging: what the system reports for each controller, to tell whether Godot's SDL
    // joypad driver (which needs extendedGamepad) can see it.
    private static func logController(_ controller: GCController) {
        let buttons = controller.input.buttons.map { "\($0.localizedName ?? "?")" }.sorted()
        NSLog("[GDRK] controller '\(controller.vendorName ?? "?")' category=\(controller.productCategory) extendedGamepad=\(controller.extendedGamepad != nil) buttons=\(buttons)")
    }

    // Resolves an anchoring source per queued controller and stages the resulting anchors for
    // the next update closure.
    private func resolvePendingControllers() {
        guard !pendingControllers.isEmpty else { return }
        let queued = pendingControllers
        pendingControllers.removeAll()

        for controller in queued {
            Task { @MainActor in
                do {
                    let source = try await AnchoringComponent.AccessoryAnchoringSource(device: controller)
                    guard let hand = Self.hand(of: source) else {
                        NSLog("[GDRK] accessory anchor: controller reports no chirality; ignoring")
                        return
                    }
                    // The startup scan and the connect notification can queue the same controller
                    // twice, so bail if this device is anchored — but let a different one replace it.
                    if let anchored = self.controllers[hand], anchored === controller {
                        return
                    }
                    guard let grip = source.locationName(named: "grip") else {
                        NSLog("[GDRK] accessory anchor: no 'grip' location for controller")
                        return
                    }
                    let aim = source.locationName(named: "aim").map {
                        AnchorEntity(.accessory(from: source, location: $0), trackingMode: .predicted)
                    }
                    NSLog("[GDRK] accessory anchor: hand=\(hand == .leftHand ? "left" : "right") aim=\(aim != nil)")
                    self.resolvedAnchors[hand] = Anchors(
                        grip: AnchorEntity(.accessory(from: source, location: grip), trackingMode: .predicted),
                        aim: aim)
                    self.controllers[hand] = controller
                } catch {
                    NSLog("[GDRK] AccessoryAnchoringSource init failed: \(error)")
                }
            }
        }
    }

    // Spatial controllers come as a handed pair, so the accessory's inherent chirality is the
    // hand it is held in.
    private static func hand(of source: AnchoringComponent.AccessoryAnchoringSource) -> ControllerHand? {
        switch source.underlyingAccessory?.inherentChirality {
        case .left: return .leftHand
        case .right: return .rightHand
        default: return nil
        }
    }
}

#endif
