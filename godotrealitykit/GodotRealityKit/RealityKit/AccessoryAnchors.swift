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
import UIKit

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

    // Each view runs its own accessory tracking session, as Apple's volume did: a session
    // shared from the first view stopped tracking once that view's scene closed.
    private var session: SpatialTrackingSession? = nil

    private var started = false
    nonisolated(unsafe) private var sceneObserver: NSObjectProtocol? = nil
    // Seconds an installed anchor may stay untracked before it is rebuilt.
    private static let reanchorDelay: TimeInterval = 2
    // When each hand's grip anchor stopped tracking, or was last rebuilt while still untracked.
    private var lostSince: [ControllerHand: TimeInterval] = [:]
    // Hands whose controller is queued again for a fresh anchor.
    private var reanchoring: Set<ControllerHand> = []
    // TEMP: device instrumentation for controllers freezing after the launcher closes.
    private var lastLog: TimeInterval = 0
    private let logID = Int.random(in: 100...999)
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
        if let observer = sceneObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    // TEMP: once a second per view, whether it still updates, wants anchors, and tracks.
    private func logState(root: RealityKit.Entity, wants: Bool) {
        let now = Date.timeIntervalSinceReferenceDate
        guard now - lastLog >= 1 else { return }
        lastLog = now
        let hands = anchors.sorted { $0.key.rawValue < $1.key.rawValue }.map { hand, anchor in
            let p = Transform(matrix: anchor.grip.transformMatrix(relativeTo: root)).translation
            let world = anchor.grip.position(relativeTo: nil)
            return "\(hand == .leftHand ? "L" : "R") grip=\(anchor.grip.isAnchored) aim=\(anchor.aim?.isAnchored ?? false) root=(\(String(format: "%.3f %.3f %.3f", p.x, p.y, p.z))) scene=(\(String(format: "%.3f %.3f %.3f", world.x, world.y, world.z)))"
        }
        NSLog("[GDRK] view \(logID): update wants=\(wants) session=\(session != nil) anchors=\(anchors.count) \(hands.joined(separator: " "))")
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
        let wants = delegate?.wantsControllerAnchors() ?? false
        logState(root: root, wants: wants)
        guard let delegate, wants else { return }

        startIfNeeded()
        reanchorLostControllers()
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

        Task { @MainActor in
            let session = SpatialTrackingSession()
            let unavailable = await session.run(SpatialTrackingSession.Configuration(tracking: [.accessory]))
            if let unavailable {
                NSLog("[GDRK] accessory tracking unavailable: \(unavailable)")
            }
            self.session = session
        }

        // Closing one of the app's scenes, such as the main window, can leave accessory anchors
        // untracked until a controller connects again, so anchor them afresh.
        sceneObserver = NotificationCenter.default.addObserver(
            forName: UIScene.didDisconnectNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                NSLog("[GDRK] accessory anchor: a scene disconnected; re-anchoring")
                for hand in self.controllers.keys {
                    self.reanchor(hand)
                }
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

    // Anchors stop tracking for good in some cases, such as after the main window closes, while
    // their controller stays connected; a fresh anchor from the same controller tracks again.
    // A hand untracked for reanchorDelay is rebuilt, then retried at that interval.
    private func reanchorLostControllers() {
        let now = Date.timeIntervalSinceReferenceDate
        for (hand, anchor) in anchors {
            if anchor.grip.isAnchored {
                lostSince[hand] = nil
                continue
            }
            let since = lostSince[hand] ?? now
            lostSince[hand] = since
            if now - since >= Self.reanchorDelay {
                NSLog("[GDRK] accessory anchor: \(hand == .leftHand ? "left" : "right") untracked for \(String(format: "%.1f", now - since))s; re-anchoring")
                lostSince[hand] = now
                // A rebuild that never resolved doesn't block the retry.
                reanchoring.remove(hand)
                reanchor(hand)
            }
        }
    }

    // Queues a hand's controller to be anchored afresh, if it is still connected.
    private func reanchor(_ hand: ControllerHand) {
        guard let controller = controllers[hand], !reanchoring.contains(hand),
              GCController.controllers().contains(where: { $0 === controller }) else { return }
        reanchoring.insert(hand)
        pendingControllers.append(controller)
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
                    if let anchored = self.controllers[hand], anchored === controller,
                       !self.reanchoring.contains(hand) {
                        return
                    }
                    self.reanchoring.remove(hand)
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
