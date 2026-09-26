//===----------------------------------------------------------------------===//
// Copyright © 2026 Apple Inc.
//
// Licensed under the MIT license (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
// LICENSE
//
//===----------------------------------------------------------------------===//

import RealityKit
import Spatial
import SwiftUI
@preconcurrency import GameController

#if os(macOS)
import AppKit
#else
import ARKit
import AVFoundation
import Combine
import UIKit
#endif

public enum ScenePresentationStyle : String, Sendable {
    case sharedVolumetric = "shared-volumetric"
    case sharedPortal = "shared-portal"
    case immersive = "immersive"
}

public enum SceneImmersionStyle : Sendable {
    case mixed
    case full
    case progressive
}

extension RealityView {
#if os(macOS)
    public typealias Size = CGSize
#else
    public typealias Size = Size3D
#endif

#if os(macOS)
    public typealias Value = SpatialEventCollection
#else
    public typealias Value = EntityTargetValue<SpatialEventCollection>
#endif

#if os(macOS)
    private func calculateRay(delegate: GDRKBridgeDelegate?,
                              event: SpatialEventCollection.Event,
                              value: SpatialEventCollection,
                              size: CGSize) -> GDRKRay? {
        guard let rawCameraPointer = delegate?.getCameraEntity() else {
            return  nil
        }

        let camera = Unmanaged<RealityKit.Entity>.fromOpaque(rawCameraPointer).takeRetainedValue()
        if let cameraComponent = camera.components[PerspectiveCameraComponent.self] {
            let projectiveTransform = ProjectiveTransform3DFloat(
                fovY: Angle2DFloat(degrees: cameraComponent.fieldOfViewInDegrees),
                aspectRatio: Float(size.width / size.height),
                nearZ: cameraComponent.near,
                farZ: cameraComponent.far,
                reverseZ: true)

            guard let invProjectiveTransform = projectiveTransform.inverse?.matrix else {
                return nil
            }

            let locationN = (SIMD2<Double>(event.location.x, event.location.y) /
                             SIMD2<Double>(size.width, size.height))
            let locationNDC = (locationN * 2.0 - 1.0) * SIMD2<Double>(1.0, -1.0)
            let locationH = invProjectiveTransform *
            simd_float4(Float(locationNDC.x), Float(locationNDC.y), 1.0, 1.0)
            let direction3D = SIMD3<Float>(locationH.x / locationH.w,
                                           locationH.y / locationH.w,
                                           locationH.z / locationH.w)
            let worldDirection4D = camera.transform.matrix * SIMD4<Float>(direction3D.x, direction3D.y, direction3D.z, 0.0)
            let worldDirection3D = simd_normalize(SIMD3<Float>(worldDirection4D.x, worldDirection4D.y, worldDirection4D.z))

            return GDRKRay(origin: camera.transform.translation, direction: worldDirection3D)
        } else if let cameraComponent = camera.components[OrthographicCameraComponent.self] {
            let aspectRatio = Float(size.width / size.height)
            let locationN = (SIMD2<Double>(event.location.x, event.location.y) /
                             SIMD2<Double>(size.width, size.height))
            let locationNDC = (locationN - 0.5) * SIMD2<Double>(1.0, -1.0)

            let locationScaled: SIMD2<Float>
            if cameraComponent.scaleDirection == .horizontal {
                locationScaled = SIMD2<Float>(Float(locationNDC.x) * cameraComponent.scale,
                                              Float(locationNDC.y) * cameraComponent.scale / aspectRatio)
            } else {
                locationScaled = SIMD2<Float>(Float(locationNDC.x) * cameraComponent.scale * aspectRatio,
                                              Float(locationNDC.y) * cameraComponent.scale)
            }

            let worldLocation4D = camera.transform.matrix * SIMD4<Float>(locationScaled.x, locationScaled.y, 0.0, 1.0)
            let worldLocation3D = SIMD3<Float>(worldLocation4D.x, worldLocation4D.y, worldLocation4D.z)
            let worldDirection4D = camera.transform.matrix * SIMD4<Float>(0.0, 0.0, 1.0, 0.0)
            let worldDirection3D = SIMD3<Float>(worldDirection4D.x, worldDirection4D.y, worldDirection4D.z)
            return GDRKRay(origin: worldLocation3D, direction: worldDirection3D)
        } else {
            return nil
        }
    }
#else
    private func calculateRay(delegate: GDRKBridgeDelegate?,
                              event: SpatialEventCollection.Event,
                              value: EntityTargetValue<SpatialEventCollection>,
                              size: Size3D) -> GDRKRay? {
		let origin = value.convert(Point3D(x: event.location.x, y: event.location.y, z: 0.0), from: .local, to: .scene)
        let direction = normalize(value.convert(Vector3D(x: 0.0, y: 0.0, z: 1.0), from: .local, to: .scene))
        return GDRKRay(origin: origin, direction: direction)
    }
#endif

    private func findHit(hits: [CollisionCastHit], position: SIMD3<Float>?) -> CollisionCastHit? {
        guard let position = position else {
            return hits.first
        }

        return hits.reduce(Optional<(CollisionCastHit, Float)>(nil)) { best, hit in
            let distance = distance_squared(position, hit.position)
            if let (_, bestDistance) = best {
                return distance < bestDistance ? (hit, distance) : best
            } else {
                return (hit, distance)
            }
        }?.0
    }

    private func handleEvent(event: SpatialEventCollection.Event, value: Value, delegate: GDRKBridgeDelegate?, root: RealityKit.Entity, size: Size, ended: Bool) {
        let eventID = event.id.hashValue
        if event.phase == .cancelled { delegate?.cancelSpatialPress(Int64(eventID)); return }

#if os(macOS)
        let position3D: SIMD3<Float>? = nil
#else
        let position3D: SIMD3<Float>? = value.convert(event.location3D, from: .local, to: .scene)
#endif

        guard let ray = self.calculateRay(delegate: delegate, event: event, value: value, size: size) else {
            if ended { delegate?.cancelSpatialPress(Int64(eventID)) }
            return
        }

        guard let hits = root.scene?.raycast(origin: ray.origin, direction: ray.direction) else {
            if ended { delegate?.cancelSpatialPress(Int64(eventID)) }
            return
        }

        let hit = self.findHit(hits: hits, position: position3D)

#if os(macOS)
        let entityID = hit?.entity.id ?? 0
#else
        let entityID = event.targetedEntity?.id ?? 0
#endif

#if os(macOS)
        let inputDevicePose: GDRKPose? = nil
#else
        let inputDevicePose = (event.inputDevicePose?.pose3D).map{ pose in
            let poseTransform = Transform(scale: SIMD3<Float>(repeating: 1.0),
                                          rotation: value.convert(pose.rotation, from: .local, to: .scene),
                                          translation: value.convert(pose.position, from: .local, to: .scene))

            let godotPoseTransform = root.convert(transform: poseTransform, from: nil)
            return GDRKPose(position: godotPoseTransform.translation, orientation: godotPoseTransform.rotation)
        }
#endif

#if os(macOS)
        let selectionRay: GDRKRay? = nil
#else
        let selectionRay = event.selectionRay.map{ ray in
            return GDRKRay(origin: root.convert(position: value.convert(ray.origin, from: .local, to: .scene), from: nil),
                         direction: root.convert(direction: value.convert(ray.direction, from: .local, to: .scene), from: nil))
        }
#endif

#if os(macOS)
        let chirality: UInt32? = nil
#else
        let chirality = event.chirality.map{ chirality in
            chirality == .left ? UInt32(0) : UInt32(1)
        }
#endif

        delegate?.onEntityPressUpdate(Int64(eventID),
                                      ended,
                                      UInt64(entityID),
                                      position3D.map{ root.convert(position: $0, from: nil) } ?? SIMD3<Float>(),
                                      (hit?.position).map{ root.convert(position: $0, from: nil) } ?? SIMD3<Float>(),
                                      (hit?.normal).map{ normalize(root.convert(normal: $0, from: nil)) } ?? SIMD3<Float>(),
                                      Int64(hit?.shapeIndex ?? -1),
                                      inputDevicePose != nil,
                                      inputDevicePose ?? GDRKPose(),
                                      selectionRay != nil,
                                      selectionRay ?? GDRKRay(),
                                      chirality != nil,
                                      chirality ?? UInt32(1))
    }

    private func spatialEventGesture(delegate: GDRKBridgeDelegate?, root: RealityKit.Entity, size: Size) -> some Gesture {
        SpatialEventGesture()
#if !os(macOS)
            .targetedToAnyEntity()
#endif
            .onChanged{ value in

#if os(macOS)
                let events = value
#else
                let events = value.gestureValue
#endif

                for event in events {
                    self.handleEvent(event: event, value: value, delegate: delegate, root: root, size: size, ended: false)
                }
            }
            .onEnded{ value in

#if os(macOS)
                let events = value
#else
                let events = value.gestureValue
#endif

                for event in events {
                    self.handleEvent(event: event, value: value, delegate: delegate, root: root, size: size, ended: true)
                }
            }
    }

    func installGestures(delegate: GDRKBridgeDelegate?, root: RealityKit.Entity, size: Size) -> some View {
        self.simultaneousGesture(self.spatialEventGesture(delegate: delegate, root: root, size: size))
    }
}

#if !os(macOS)

// Stores the bounds of the Swift UI View in RealityKit scene space
class PortalRealityViewState {
    var lastViewBounds: BoundingBox? = nil
    var lastCageScale: Float? = nil
}

// Workaround for : RealityKit's RealityView does not receive
// .handlesGameControllerEvents when the gaze target is inside the view (e.g.
// the portal surface), because the GC input remote effect is applied on a
// layer upstream from the CA hit-test leaf. A collision cage around the view
// provides a valid hit-test destination so gamepad events reach the app.
private func createGamepadInputCagePlane(
        size: SIMD3<Float>,
        position: SIMD3<Float>) -> RealityKit.Entity {
    let entity = RealityKit.Entity()
    entity.position = position
    var collision = CollisionComponent(shapes: [.generateBox(size: size)], mode: .trigger)
    collision.isStatic = true
    entity.components.set(collision)
    entity.components.set(InputTargetComponent(allowedInputTypes: .all))
    return entity
}

private func createGamepadInputCage(size: SIMD3<Float>, thickness: Float = 0.01) -> RealityKit.Entity {
    let halfSize = size / 2
    let halfThickness = thickness / 2
    let container = RealityKit.Entity()

    let frontBackSize = SIMD3<Float>(size.x, size.y, thickness)
    let leftRightSize = SIMD3<Float>(thickness, size.y, size.z)
    let topBottomSize = SIMD3<Float>(size.x, thickness, size.z)

    container.addChild(createGamepadInputCagePlane(size: frontBackSize,
            position: SIMD3(0, 0, halfSize.z - halfThickness)))
    container.addChild(createGamepadInputCagePlane(size: frontBackSize,
            position: SIMD3(0, 0, -halfSize.z + halfThickness)))
    container.addChild(createGamepadInputCagePlane(size: leftRightSize,
            position: SIMD3(-halfSize.x + halfThickness, 0, 0)))
    container.addChild(createGamepadInputCagePlane(size: leftRightSize,
            position: SIMD3(halfSize.x - halfThickness, 0, 0)))
    container.addChild(createGamepadInputCagePlane(size: topBottomSize,
            position: SIMD3(0, halfSize.y - halfThickness, 0)))
    container.addChild(createGamepadInputCagePlane(size: topBottomSize,
            position: SIMD3(0, -halfSize.y + halfThickness, 0)))
    return container
}

// Shows a 2D portal into the game in place of Godot's Camera3D
struct PortalRealityView : View {
    let root: RealityKit.Entity
    let delegate: GDRKBridgeDelegate?

    let portal = RealityKit.Entity()
    let state = PortalRealityViewState()

    @State private var subscription: EventSubscription? = nil

    @State private var worldScaleExponent: Float = -1; // 1/10 of the size

    @Environment(\.physicalMetrics) private var physicalMetrics

    @State private var interactionTarget: RealityKit.Entity?

    var worldScale: Float {
        let fixedWorldScale = self.fixedWorldScale
        if fixedWorldScale != 0 {
            return fixedWorldScale
        }
        return 1.0 / pow(10.0, self.worldScaleExponent)
    }

    // Set via reality_kit/portal_presentation_world_scale; 0 means unset, use the interactive slider instead.
    private var fixedWorldScale: Float {
        delegate?.getExtensionSettings().portalWorldScale ?? 0
    }

    private var handlesGameControllerEvents: Bool {
        delegate?.getExtensionSettings().handlesGameControllerEvents ?? true
    }

    private func updateInteractionTarget(_ target: RealityKit.Entity, in proxy: GeometryProxy3D) {
        let size = physicalMetrics.convert(proxy.size, to: .meters)
        let minimumDimension: CGFloat = 1.0
        let maxDimension = Swift.max(size.width, Swift.max(size.height, size.depth))
        let scale = Float(Swift.max(maxDimension, minimumDimension))
        if state.lastCageScale != scale {
            target.transform.scale = SIMD3(repeating: scale)
            state.lastCageScale = scale
        }
    }

    public var body: some View {
        GeometryReader3D{ proxy in
            RealityView(make: { content in
                self.root.components.set(WorldComponent())

                self.portal.components.set(PortalComponent(target: self.root))

                content.add(self.root)
                content.add(self.portal)
                if self.handlesGameControllerEvents {
                    let cage = createGamepadInputCage(size: SIMD3<Float>(0.94, 0.43, 0.40))
                    content.add(cage)
                    self.updateInteractionTarget(cage, in: proxy)
                    self.interactionTarget = cage
                }

                self.subscription = content.subscribe(to: SceneEvents.Update.self, self.onSceneUpdate)
                self.delegate?.onWorldScaleChanged(self.worldScale)
            }, update: { content in
                let viewBounds = content.convert(proxy.frame(in: .local), from: .local, to: .scene)
                if self.state.lastViewBounds != viewBounds {
                    let portalMesh = RealityKit.MeshResource.generatePlane(width: viewBounds.extents.x,
                                                                           height: viewBounds.extents.y,
                                                                           cornerRadius: 0.02)
                    let portalModel = ModelComponent(mesh: portalMesh,
                                                     materials: [PortalMaterial()])
                    self.portal.components[ModelComponent.self] = portalModel
                    self.state.lastViewBounds = viewBounds
                }

                if let target = self.interactionTarget {
                    self.updateInteractionTarget(target, in: proxy)
                }

                self.delegate?.onWindowResized(simd_float3(proxy.size.vector))
            })
            .installGestures(delegate: self.delegate, root: self.root, size: proxy.size)
            .setupProjectSettings(from: delegate, portalMode: true)
            .offset(z: -(proxy.size.depth / 2) + 1)
            .realityViewLayoutBehavior(.centered)
        }
        if self.fixedWorldScale == 0 {
            Slider(value: $worldScaleExponent, in: -8.0 ... 8.0, label: { Text("World Scale") })
                .padding()
                .onChange(of: self.worldScale) {
                    self.delegate?.onWorldScaleChanged(self.worldScale)
                }
        }
    }

    private func onSceneUpdate(event: SceneEvents.Update) {
        self.updateCamera()
    }

    private func updateCamera() {

        if let rawCameraPointer = delegate?.getCameraEntity() {
            let camera = Unmanaged<RealityKit.Entity>.fromOpaque(rawCameraPointer).takeRetainedValue()
            let invWorldScale = SIMD3<Float>(repeating: Float(1.0 / self.worldScale));
            let normalized = Transform(scale: invWorldScale * camera.transform.scale,
                                       rotation: camera.transform.rotation,
                                       translation: camera.transform.translation)
            self.root.components[Transform.self] = Transform(matrix: normalized.matrix.inverse)
        } else {
            self.root.components[Transform.self] = Transform()
        }
    }
}

extension SwiftUI.View {
    // In portal mode, pair with a collision cage () so gamepad
    // events are delivered even when the gaze target is inside the RealityView.
    func setupProjectSettings(from delegate: GDRKBridgeDelegate?, portalMode: Bool = false) -> some View {
        let handles = delegate?.getExtensionSettings().handlesGameControllerEvents ?? true
        return self.handlesGameControllerEvents(
            matching: handles ? .gamepad : [],
            withOptions: (handles && portalMode) ? .receivesEventsInView(false) : nil)
    }
}

@Observable
class ImmersiveRealityViewState {
    @MainActor static let shared = ImmersiveRealityViewState()
    var lastScale: SIMD3<Float>? = nil
    var hasInputTargets: Bool = false
}

// Shows the Godot scene in an immersive space
struct ImmersiveRealityView : View {
    let root: RealityKit.Entity
    let delegate: GDRKBridgeDelegate?
    
    let state = ImmersiveRealityViewState()

    @State private var subscription: EventSubscription? = nil

    public var body: some View {
        // Read sceneReady so toggling it triggers a body re-evaluation.
        let _ = state.hasInputTargets
        GeometryReader3D{ proxy in
            RealityView(make: { content in
                content.add(self.root)
                self.subscription = content.subscribe(to: SceneEvents.Update.self, self.onSceneUpdate)
            }, update: { content in
            })
            .installGestures(delegate: self.delegate, root: self.root, size: proxy.size)
            .setupProjectSettings(from: delegate)
        }
    }

    private func onSceneUpdate(event: SceneEvents.Update) {
        if let xrOrigin = delegate?.getXROrigin() {
            if xrOrigin.scale != state.lastScale {
                // Assuming all scale components are the same
                delegate?.onWorldScaleChanged(xrOrigin.scale.min())
                state.lastScale = xrOrigin.scale
            }

            let worldScale = xrOrigin.scale
            let worldRotation = xrOrigin.orientation.inverse
            let worldTranslation = -worldScale * simd_act(worldRotation, xrOrigin.position)
            self.root.components.set(Transform(scale: worldScale, rotation: worldRotation, translation: worldTranslation))
        }
    }
}

// Explicit ARKit ownership gives us provider lifecycle events and valid tracking states.
// SpatialTrackingSession is not also run for these controllers: one owner publishes poses.
@MainActor
final class SharedAccessoryTracking {
    static let shared = SharedAccessoryTracking()
    private var clients = 0
    func synchronize() {
        let enabled = Bridge.delegate?.controllerTrackingEnabled() ?? false
        if enabled && clients == 0 { acquire() }
        if !enabled && clients > 0 { release() }
        guard enabled else { return }
        for hand in [ControllerHand.leftHand, .rightHand] {
            let pointer = controllers[hand].map { Unmanaged.passUnretained($0).toOpaque() }
            Bridge.delegate?.setControllerInput(hand, pointer, locations[hand] ?? 0)
        }
    }
    func stop() { clients = 0; worker?.cancel() }
    private(set) var locations: [ControllerHand: UInt32] = [:]
    func report(_ error: String = "") {
        error.withCString { Bridge.delegate?.setControllerTrackingState(running, $0) }
    }
    private var worker: Task<Void, Never>?
    private var disconnectObserver: NSObjectProtocol?
    private init() {
        disconnectObserver = NotificationCenter.default.addObserver(forName: .GCControllerDidDisconnect, object: nil, queue: .main) { [weak self] notification in
            guard let controller = notification.object as? GCController else { return }
            let identity = ObjectIdentifier(controller)
            MainActor.assumeIsolated {
                guard let self else { return }
                for hand in [ControllerHand.leftHand, .rightHand] where self.controllers[hand].map(ObjectIdentifier.init) == identity {
                    self.controllers.removeValue(forKey: hand)
                    self.locations.removeValue(forKey: hand)
                    self.anchors.removeValue(forKey: hand)
                    Bridge.delegate?.setControllerInput(hand, nil, 0)
                }
            }
        }
    }
    func acquire() {
        clients += 1
        guard clients == 1 else { return }
        let previous = worker
        worker = Task { @MainActor in
            await previous?.value
            guard !Task.isCancelled else { return }
            await self.run()
        }
    }
    func release() {
        clients = max(0, clients - 1)
        if clients == 0 { worker?.cancel() }
    }
    private let session = ARKitSession()
    private(set) var anchors: [ControllerHand: AccessoryAnchor] = [:]
    private(set) var anchorUpdated: [ControllerHand: CFTimeInterval] = [:]
    private(set) var controllers: [ControllerHand: GCController] = [:]
    private(set) var running = false
    private var provider: AccessoryTrackingProvider?
    private var anchorTask: Task<Void, Never>?
    private var trackingStates: [ControllerHand: String] = [:]

    func run() async {
        guard AccessoryTrackingProvider.isSupported else {
            NSLog("[GDRK Tracking] AccessoryTrackingProvider unsupported")
            return
        }
        let events = Task { @MainActor [weak self, session] in
            for await event in session.events {
                guard !Task.isCancelled else { break }
                guard let self else { break }
                switch event {
                case .dataProviderStateChanged(_, let state, let error):
                    // Use our current provider state; an old provider can stop on reconnect.
                    self.running = self.provider?.state == .running
                    if !self.running { self.anchors.removeAll() }
                    self.report(error.map { String(describing: $0) } ?? "")
                    NSLog("[GDRK Tracking] provider event=\(state) current=\(String(describing: self.provider?.state)) error=\(String(describing: error))")
                case .authorizationChanged(let type, let status):
                    NSLog("[GDRK Tracking] authorization \(type)=\(status)")
                    if status == .denied { self.report("Accessory tracking authorization denied") }
                default: break
                }
            }
        }
        defer {
            events.cancel()
            anchorTask?.cancel()
            session.stop()
            provider = nil
            running = false
            anchors.removeAll()
            controllers.removeAll(); locations.removeAll()
            report()
            for hand in [ControllerHand.leftHand, .rightHand] { Bridge.delegate?.setControllerInput(hand, nil, 0) }
        }
        var previous: Set<ObjectIdentifier>? = nil
        // Polling also handles controllers already connected before notification registration.
        // Reconfiguration is serialized, so two connects cannot race session.run().
        while !Task.isCancelled {
            let connected = GCController.controllers().filter {
                $0.productCategory == GCProductCategorySpatialController
            }
            let identities = Set(connected.map(ObjectIdentifier.init))
            if identities != previous {
                previous = identities
                anchorTask?.cancel()
                session.stop()
                running = false
                anchors.removeAll()
                controllers = controllers.filter { identities.contains(ObjectIdentifier($0.value)) }
                locations = locations.filter { controllers[$0.key] != nil }
                trackingStates.removeAll()
                var accessories: [Accessory] = []
                for controller in connected {
                    do {
                        let accessory = try await Accessory(device: controller)
                        guard !Task.isCancelled else { return }
                        let hand: ControllerHand
                        switch accessory.inherentChirality {
                        case .left: hand = .leftHand
                        case .right: hand = .rightHand
                        default: continue
                        }
                        accessories.append(accessory)
                        controllers[hand] = controller
                        locations[hand] = (accessory.locations.contains(.grip) ? 1 : 0) |
                            (accessory.locations.contains(.aim) ? 2 : 0) | (accessory.locations.contains(.gripSurface) ? 4 : 0)
                        NSLog("[GDRK Tracking] configured \(controller.vendorName ?? "controller") hand=\(hand)")
                    } catch {
                        self.report("Accessory setup failed: \(error)")
                    }
                }
                if !accessories.isEmpty {
                    let next = AccessoryTrackingProvider(accessories: accessories)
                    provider = next
                    do {
                        try await session.run([next])
                        guard !Task.isCancelled else { return }
                        running = next.state == .running
                        report()
                        NSLog("[GDRK Tracking] session.run returned; provider=\(next.state), accessories=\(accessories.count)")
                        anchorTask = Task { @MainActor [weak self] in
                            for await update in next.anchorUpdates {
                                guard !Task.isCancelled else { break }
                                guard let self else { break }
                                self.running = next.state == .running
                                let hand: ControllerHand
                                switch update.anchor.accessory.inherentChirality {
                                case .left: hand = .leftHand
                                case .right: hand = .rightHand
                                default: continue
                                }
                                let status = "\(update.event):\(update.anchor.trackingState)"
                                if self.trackingStates[hand] != status {
                                    self.trackingStates[hand] = status
                                    NSLog("[GDRK Tracking] hand=\(hand) anchor=\(status)")
                                }
                                switch update.event {
                                case .added, .updated:
                                    self.anchors[hand] = update.anchor
                                    self.anchorUpdated[hand] = CACurrentMediaTime()
                                case .removed:
                                    self.anchors.removeValue(forKey: hand)
                                }
                            }
                        }
                    } catch {
                        self.report("Accessory tracking failed: \(error)")
                    }
                } else {
                    provider = nil
                    NSLog("[GDRK Tracking] no spatial accessories to run")
                }
            }
            do { try await Task.sleep(for: .milliseconds(500)) }
            catch { break }
        }
    }
}

@MainActor
class SharedVolumetricRealityViewState {
    var lastCameraTransform: Transform? = nil
    var lastViewBounds: BoundingBox? = nil
    var lastScale: Float? = nil
    let tracking = SharedAccessoryTracking.shared
    var trackingLease: UUID?
    var lastPoseLog: TimeInterval = 0
    var poseStatus: [ControllerHand: String] = [:]
}

// Shows the Godot scene in a volumetric window.
// If the scene has a RealityVolumeCamera3D it shows what is inside the volume camera,
// scaled to fit the volumetric window.
// otherwise it scales down the whole world to fit in the volumetric window
struct SharedVolumetricRealityView : View {
    @Environment(\.scenePhase) private var scenePhase
    let root: RealityKit.Entity
    let delegate: GDRKBridgeDelegate?

    @State private var anchor = RealityKit.Entity()

    @State private var state = SharedVolumetricRealityViewState()

    @State private var subscription: EventSubscription? = nil

    public var body: some View {
        GeometryReader3D{
            proxy in
                RealityView(make: { content in
                    self.anchor.addChild(self.root)
                    content.add(self.anchor)
                    self.subscription = content.subscribe(to: SceneEvents.Update.self, self.onSceneUpdate)
            }, update: { content in
                   let viewBounds = content.convert(proxy.frame(in: .local), from: .local, to: .scene)
                   self.updateCamera(viewBounds: viewBounds)
                   self.delegate?.onVolumeSizeChanged(viewBounds.extents)
                   self.delegate?.onWindowResized(simd_float3(proxy.size.vector))
            })
             .installGestures(delegate: self.delegate, root: self.root, size: proxy.size)
            .realityViewLayoutBehavior(.flexible)
            .setupProjectSettings(from: delegate)
            .onDisappear {
                for hand in [ControllerHand.leftHand, .rightHand] {
                    self.delegate?.setControllerAnchor(hand, GDRKTransform(scale: .one, position: .zero, orientation: simd_quatf()), false)
                }
            }
        }
    }

    // CoordinateSpace3D conversion includes the volume camera's world scale/rotation.
    // Raw ARKit world transforms must never be sent directly to Godot scene-local trackers.
    private func publishControllerPoses() {
        guard scenePhase != .background, let delegate, delegate.wantsControllerAnchors() else { return }
        let locations: [Accessory.LocationName] = [.grip, .aim, .gripSurface]
        for hand in [ControllerHand.leftHand, .rightHand] {
            let accessory = state.tracking.anchors[hand]
            for (index, location) in locations.enumerated() {
                var pose = Transform()
                var velocity = SIMD3<Float>.zero
                var angular = SIMD3<Float>.zero
                var confidence: Int32 = 0
                let supported = (state.tracking.locations[hand] ?? 0) & (1 << index) != 0
                if supported, state.tracking.running, CACurrentMediaTime() - (state.tracking.anchorUpdated[hand] ?? 0) < 0.5, let accessory,
                   accessory.trackingState == .positionOrientationTracked || accessory.trackingState == .positionOrientationTrackedLowAccuracy {
                    do {
                        pose = Transform(matrix: try root.transform(from: accessory.coordinateSpace(for: location, correction: .none)).matrix)
                        let anchor = Transform(matrix: try root.transform(from: accessory.coordinateSpace(correction: .none)).matrix)
                        // ARKit velocities use the accessory's coordinate space. Translation is
                        // converted to Godot units; angular velocity is rotated, never scaled.
                        angular = anchor.rotation.act(accessory.angularVelocity)
                        velocity = anchor.rotation.act(anchor.scale * accessory.velocity) + simd_cross(angular, pose.translation - anchor.translation)
                        confidence = accessory.trackingState == .positionOrientationTracked ? 2 : 1
                    } catch {
                        let message = "Volume coordinate conversion failed: \(error)"
                        if state.poseStatus[hand] != message {
                            state.poseStatus[hand] = message
                            message.withCString { delegate.setControllerTrackingState(state.tracking.running, $0) }
                        }
                    }
                }
                delegate.setControllerPose(hand, Int32(index), GDRKTransform(scale: .one, position: pose.translation, orientation: pose.rotation), velocity, angular, confidence, supported)
            }
        }
    }

    private func onSceneUpdate(event: SceneEvents.Update) {
        if let viewBounds = self.state.lastViewBounds {
            self.updateCamera(viewBounds: viewBounds)
        }
        self.publishControllerPoses()

    }

    private func updateCamera(viewBounds: BoundingBox) {
        var cameraTransform: Transform! = nil
        if let rawCameraPointer = delegate?.getCameraEntity() {
            let camera = Unmanaged<RealityKit.Entity>.fromOpaque(rawCameraPointer).takeRetainedValue()
            if let volumetricCameraSize = camera.components[VolumeCameraComponent.self]?.size {
                cameraTransform = camera.transform
                cameraTransform.scale *= volumetricCameraSize;
            }
        }

        if cameraTransform == nil {
            if !self.root.children.isEmpty {
                let rootBounds = self.root.visualBounds(relativeTo: self.anchor)
                if !rootBounds.isEmpty {
                    cameraTransform = Transform(scale: rootBounds.extents,
                                                rotation: simd_quatf(ix: 0.0, iy: 0.0, iz: 0.0, r: 1.0),
                                                translation: rootBounds.center)
                } else {
                    cameraTransform = Transform()
                }
            } else {
                cameraTransform = Transform()
            }
        }

        let worldScale = (viewBounds.extents / cameraTransform.scale).min()
        let viewBoundsChanged =  self.state.lastViewBounds != viewBounds
        let scaleChanged = self.state.lastScale != worldScale

        // For now, we assume that the volume camera component size does not change.
        // We only adapt to changes in view bounds
        if self.state.lastCameraTransform?.translation != cameraTransform.translation ||
            self.state.lastCameraTransform?.rotation != cameraTransform.rotation ||
            scaleChanged || viewBoundsChanged
        {
            let worldRotation = cameraTransform.rotation.inverse
            var worldTranslation = -worldScale * simd_act(worldRotation, cameraTransform.translation)

            if scaleChanged {
                self.state.lastScale = worldScale
                self.delegate?.onWorldScaleChanged(worldScale)
            }

            worldTranslation.y -= 0.5 * (viewBounds.extents.y - worldScale * cameraTransform.scale.y)

            self.anchor.components[Transform.self] = Transform(scale: SIMD3<Float>(repeating: worldScale),
                                                               rotation: worldRotation,
                                                               translation: worldTranslation)

            delegate?.setPHASETransform(GDRKTransform(
                scale: SIMD3<Float>(repeating: worldScale),
                position: worldTranslation,
                orientation: worldRotation
            ))

            self.state.lastCameraTransform = cameraTransform
            self.state.lastViewBounds = viewBounds
        }
    }
}

class LoadingViewController: UIViewController {
    override func loadView() {
        let loadingView = UIView()
        loadingView.backgroundColor = Bridge.bootSplashBgColor

        if let bootImage = Bridge.bootSplashImage {
            let imageView = UIImageView(image: bootImage)
            imageView.contentMode = .scaleAspectFit
            imageView.translatesAutoresizingMaskIntoConstraints = false
            loadingView.addSubview(imageView)

            NSLayoutConstraint.activate([
                imageView.centerXAnchor.constraint(equalTo: loadingView.centerXAnchor),
                imageView.centerYAnchor.constraint(equalTo: loadingView.centerYAnchor),
                imageView.widthAnchor.constraint(lessThanOrEqualTo: loadingView.widthAnchor),
                imageView.heightAnchor.constraint(lessThanOrEqualTo: loadingView.heightAnchor),
            ])
        }

        view = loadingView
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        guard let request = UISceneSessionActivationRequest(hostingDelegateClass: BridgeScene.self, id: Bridge.presentationStyle.rawValue) else {
            print("Unable to create gdrk UISceneSessionActivationRequest!")
            if Bridge.presentationStyle == .sharedVolumetric { Bridge.volumeWindows[0]?.activationFailed("Unable to create main volume activation request") }
            return
        }

        if Bridge.presentationStyle == .sharedVolumetric { Bridge.volumeWindows[0]?.watchActivation() }
        UIApplication.shared.activateSceneSession(for: request) { error in
            print("Error activating gdrk scene session: \(error)")
            if Bridge.presentationStyle == .sharedVolumetric { Bridge.volumeWindows[0]?.activationFailed(error.localizedDescription) }
        }
    }
}

class GodotViewController: UIViewController {
    private static var activeControllers: [GodotViewController] = []
    private static var drawing = false
    let godotViewController: UIViewController? = Bridge.originalViewController

    var displayLink: CADisplayLink? = nil
    var isActive: Bool = false

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        startRendering()
    }

    func startRendering() {
        guard !self.isActive, let godotView = godotViewController?.view else { return }
        self.isActive = true
        Self.activeControllers.append(self)
        displayLink = CADisplayLink(target: self, selector: #selector(update))
        if let framerate = godotView.value(forKey: "preferredFrameRate") as? Int {
            displayLink?.preferredFramesPerSecond = framerate
        }
        displayLink?.add(to: .current, forMode: .common)
        displayLink?.isPaused = Self.activeControllers.first !== self
    }

    @objc
    func update() {
        guard Self.activeControllers.first === self, !Self.drawing else { return }
        Self.drawing = true
        SharedAccessoryTracking.shared.synchronize()
        // The problem: inside drawView, Godot temporarily hands control back to the system's main
        // run loop (the mechanism iOS uses to process events like touches, timers, and other
        // callbacks while an app is idle) so that any input events waiting to be delivered get
        // handled immediately, instead of waiting until drawView returns. Godot pauses its own
        // CADisplayLink first so that handing control back to the run loop can't turn around and
        // call drawView again through its own display link. But Godot has no idea our separate
        // CADisplayLink exists, so it doesn't pause it. That means while control is handed back to
        // the run loop, our CADisplayLink can fire, which calls update(), which calls drawView
        // again - all before the first drawView call has returned. That inner drawView call does
        // the exact same thing, calling drawView a third time, and so on, forever, until the app
        // runs out of stack space and crashes.
        // The fix: pause our own CADisplayLink before calling drawView, the same way Godot pauses
        // its own, so it can't fire again while we're still inside drawView. Resume it once
        // drawView returns.
        displayLink?.isPaused = true
        defer {
            Self.drawing = false
            if Self.activeControllers.first === self { displayLink?.isPaused = false }
        }

        if let godotView = godotViewController?.view {
            // If the view was active, it means that the a display link is installed to update the
            // view. To remove it, we call `stopRendering`
            let viewIsActive: Bool =  godotView.value(forKey: "isActive") as! Bool
            if (viewIsActive) {
                if godotView.responds(to: Selector(("stopRendering"))) {
                    godotView.perform(Selector(("stopRendering")))
                } else {
                    print("GodotRealityKit Error: missing function 'stopRendering' on Godot's GDTView")
                }
            }
            
            // The GDTView drawView will only run if `isActive` is true. So we force it here
            // and reverse it back after the view has been updated.
            godotView.setValue(true, forKey: "isActive")
            if godotView.responds(to: Selector(("drawView"))) {
                godotView.perform(Selector(("drawView")))
            } else {
                print("GodotRealityKit Error: missing function 'drawView' on Godot's GDTView")
            }
            godotView.setValue(false, forKey: "isActive")
        }

    }

    func stopRendering() {
        if !self.isActive {
            return
        }

        self.isActive = false
        let wasDriver = Self.activeControllers.first === self
        Self.activeControllers.removeAll { $0 === self }
        self.displayLink?.invalidate()
        self.displayLink = nil
        if wasDriver { Self.activeControllers.first?.displayLink?.isPaused = false }
        if Self.activeControllers.isEmpty { SharedAccessoryTracking.shared.stop() }
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        stopRendering()
    }

    override func pressesBegan(
        _ presses: Set<UIPress>,
        with event: UIPressesEvent?
    ) {
        self.godotViewController?.pressesBegan(presses, with: event)
    }

    override func pressesEnded(
        _ presses: Set<UIPress>,
        with event: UIPressesEvent?
    ) {
        self.godotViewController?.pressesEnded(presses, with: event)
    }
}

struct GodotViewControllerRepresentable : UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> GodotViewController {
        return GodotViewController()
    }

    func updateUIViewController(_ uiViewController: GodotViewController, context: Context) {}

    static func dismantleUIViewController(_ uiViewController: GodotViewController, coordinator: ()) {
        uiViewController.stopRendering()
    }
}

@MainActor private enum Godot2DWindowRequests {
    static var opened = Set<UInt64>()
    private static var observers: [NSObjectProtocol] = []
    private static var generations: [UInt64: UInt64] = [:]

    static func install() {
        guard observers.isEmpty else { return }
        observers.append(NotificationCenter.default.addObserver(forName: Notification.Name("org.godotengine.visionos.openWindow"), object: nil, queue: .main) { notification in
            guard let id = notification.object as? UInt64 else { return }
            MainActor.assumeIsolated {
                guard opened.insert(id).inserted else { return }
                let generation = (generations[id] ?? 0) + 1
                generations[id] = generation
                guard let request = UISceneSessionActivationRequest(hostingDelegateClass: Godot2DWindowScene.self, id: "gdrk-2d", value: id) else {
                    opened.remove(id)
                    "Unable to create 2D activation request".withCString { Bridge.delegate?.on2DWindowFailed(id, $0) }
                    return
                }
                UIApplication.shared.activateSceneSession(for: request) { error in
                    guard generations[id] == generation, opened.contains(id) else { return }
                    opened.remove(id)
                    error.localizedDescription.withCString { Bridge.delegate?.on2DWindowFailed(id, $0) }
                }
            }
        })
        observers.append(NotificationCenter.default.addObserver(forName: Notification.Name("org.godotengine.visionos.closeWindow"), object: nil, queue: .main) { notification in
            guard let id = notification.object as? UInt64 else { return }
            MainActor.assumeIsolated {
                opened.remove(id)
                generations[id] = (generations[id] ?? 0) + 1
            }
        })
    }
}

@MainActor private enum GodotSceneVisibility {
    static var foregroundScenes = Set<UUID>()

    static func update(_ id: UUID, phase: ScenePhase) {
        if phase == .background {
            foregroundScenes.remove(id)
        } else {
            foregroundScenes.insert(id)
        }
        Bridge.sceneVisible = !foregroundScenes.isEmpty
    }

    static func remove(_ id: UUID) {
        foregroundScenes.remove(id)
        Bridge.sceneVisible = !foregroundScenes.isEmpty
    }
}

private struct GodotSceneVisibilityBridge: ViewModifier {
    @Environment(\.scenePhase) private var scenePhase
    @State private var id = UUID()

    func body(content: Content) -> some View {
        content
            .onAppear { GodotSceneVisibility.update(id, phase: scenePhase) }
            .onDisappear { GodotSceneVisibility.remove(id) }
            .onChange(of: scenePhase) { _, phase in
                GodotSceneVisibility.update(id, phase: phase)
            }
    }
}

private struct Godot2DWindowController: UIViewControllerRepresentable {
    let id: UInt64

    func makeUIViewController(context: Context) -> UIViewController {
        guard let controllerType = NSClassFromString("GDTViewController") as? UIViewController.Type else {
            assertionFailure("Godot 2D window controller is unavailable")
            return UIViewController()
        }
        let controller = controllerType.init(nibName: nil, bundle: nil)
        controller.setValue(NSNumber(value: id), forKey: "godotWindowID")
        return controller
    }

    func updateUIViewController(_ controller: UIViewController, context: Context) {}
}

private struct Godot2DWindow: View {
    let id: UInt64
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Godot2DWindowController(id: id)
            .overlay { GodotViewControllerRepresentable().allowsHitTesting(false) }
            .ignoresSafeArea()
            .onAppear {
                if !Godot2DWindowRequests.opened.contains(id) { dismiss() }
            }
            .onDisappear { Godot2DWindowRequests.opened.remove(id) }
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("org.godotengine.visionos.closeWindow"))) { notification in
                if notification.object as? UInt64 == id {
                    Godot2DWindowRequests.opened.remove(id)
                    dismiss()
                }
            }
    }
}

class Godot2DWindowScene: NSObject, @MainActor UIHostingSceneDelegate {
    static var rootScene: some SwiftUI.Scene {
        WindowGroup("Godot 2D", id: "gdrk-2d", for: UInt64.self) { $id in
            if let id { Godot2DWindow(id: id).modifier(GodotSceneVisibilityBridge()) }
        }
        .defaultSize(width: 960, height: 600)
        .restorationBehavior(.disabled)
    }
}

private struct StaleVolumeWindow: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View { Color.clear.onAppear { dismiss() } }
}

private struct VolumeSessionKey: Codable, Hashable {
    let id: UInt64
    let generation: UInt64
}

@MainActor @Observable
final class VolumeWindowRecord {
    let root: RealityKit.Entity
    let delegate: GDRKBridgeDelegate
    let id: UInt64
    let generation: UInt64
    var title = ""
    var initial = SIMD3<Float>.zero
    var minimum = SIMD3<Float>.zero
    var maximum = SIMD3<Float>.zero
    var resizeMode: Int32 = 0
    var baseplate: Int32 = 0
    var fixedSize = SIMD3<Float>.zero
    weak var scene: UIWindowScene?
    var closeRequested = false
    var finished = false
    var opening = false
    private var disconnectObserver: NSObjectProtocol?

    init(root: RealityKit.Entity, delegate: GDRKBridgeDelegate, id: UInt64, generation: UInt64) {
        self.root = root; self.delegate = delegate; self.id = id; self.generation = generation
    }

    func report(_ event: Int32, _ error: String = "") {
        error.withCString { delegate.onVolumeWindowEvent(event, $0) }
    }

    func attach(_ scene: UIWindowScene) {
        guard self.scene !== scene else { return }
        self.scene = scene
        if let observer = disconnectObserver { NotificationCenter.default.removeObserver(observer) }
        disconnectObserver = NotificationCenter.default.addObserver(forName: UIScene.didDisconnectNotification, object: scene, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.scene = nil
                self.opening = false
                self.finished = true
                self.report(1)
            }
        }
        applyGeometry()
        if closeRequested || finished || !delegate.isValid() { close(); return }
        opening = false
        report(0)
    }

    func applyGeometry() {
        guard let scene else { return }
        scene.title = title
        // UIKit geometry preferences apply to planar windows. Volume resizing is
        // expressed by the SwiftUI content bounds and windowResizability(.contentSize).

    }

    func close() {
        closeRequested = true
        guard let scene else {
            if !opening { finished = true; report(1) }
            return
        }
        UIApplication.shared.requestSceneSessionDestruction(scene.session, options: nil) { [weak self] error in
            guard let self, !self.finished else { return }
            self.closeRequested = false
            self.report(3, error.localizedDescription)
        }
    }

    func activationFailed(_ message: String) {
        guard !finished, scene == nil else { return }
        opening = false; finished = true; report(2, message)
    }

    func watchActivation() {
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(20))
            guard let self, self.opening, self.scene == nil, !self.finished else { return }
            self.activationFailed("The system did not create the requested volume")
        }
    }

    func open() {
        guard !opening, scene == nil else { return }
        opening = true
        let key = VolumeSessionKey(id: id, generation: generation)
        guard let request = UISceneSessionActivationRequest(hostingDelegateClass: AdditionalVolumeScene.self, id: "gdrk-extra-volume", value: key) else {
            opening = false; finished = true; report(2, "Unable to create volume activation request"); return
        }
        UIApplication.shared.activateSceneSession(for: request) { [weak self] error in
            guard let self, !self.finished, self.scene == nil else { return }
            self.opening = false; self.finished = true; self.report(2, error.localizedDescription)
        }
        watchActivation()
    }

    isolated deinit {
        if let disconnectObserver { NotificationCenter.default.removeObserver(disconnectObserver) }
    }
}

private struct VolumeHostObserver: UIViewRepresentable {
    let record: VolumeWindowRecord
    final class Probe: UIView {
        var record: VolumeWindowRecord?
        override func didMoveToWindow() {
            super.didMoveToWindow()
            guard let scene = window?.windowScene, let record else { return }
            Task { @MainActor in record.attach(scene) }
        }
    }
    func makeUIView(context: Context) -> Probe { let view = Probe(); view.record = record; return view }
    func updateUIView(_ view: Probe, context: Context) { view.record = record }
}

private struct VolumeWindowContent: View {
    let record: VolumeWindowRecord
    @Environment(\.physicalMetrics) private var metrics
    private func points(_ value: Float) -> CGFloat? {
        value > 0 ? metrics.convert(CGFloat(value), from: .meters) : nil
    }
    private func preferred(_ axis: Int) -> Float {
        var value = record.initial[axis]
        if value > 0 {
            value = max(value, record.minimum[axis])
            if record.maximum[axis] > 0 { value = min(value, record.maximum[axis]) }
        }
        return value
    }
    private func lower(_ axis: Int) -> CGFloat? {
        if record.opening && preferred(axis) > 0 { return points(preferred(axis)) }
        return points(record.resizeMode == 1 && record.fixedSize[axis] > 0 ? record.fixedSize[axis] : record.minimum[axis])
    }
    private func upper(_ axis: Int) -> CGFloat? {
        if record.opening && preferred(axis) > 0 { return points(preferred(axis)) }
        return points(record.resizeMode == 1 && record.fixedSize[axis] > 0 ? record.fixedSize[axis] : record.maximum[axis])
    }
    var body: some View {
        SharedVolumetricRealityView(root: record.root, delegate: record.delegate)
            .frame(minWidth: lower(0), idealWidth: points(record.initial.x), maxWidth: upper(0),
                   minHeight: lower(1), idealHeight: points(record.initial.y), maxHeight: upper(1))
            .frame(minDepth: lower(2), idealDepth: points(record.initial.z), maxDepth: upper(2))
            .volumeBaseplateVisibility(record.baseplate == 1 ? .visible : (record.baseplate == 2 ? .hidden : .automatic))
            .overlay { GodotViewControllerRepresentable() }
            .background { VolumeHostObserver(record: record).frame(width: 0, height: 0).allowsHitTesting(false) }
            .ornament(attachmentAnchor: .scene(.bottom)) {
                if !record.title.isEmpty { Text(record.title).padding(12).glassBackgroundEffect() }
            }
            .modifier(GodotSceneVisibilityBridge())
    }
}

class AdditionalVolumeScene: NSObject, @MainActor UIHostingSceneDelegate {
    static var rootScene: some SwiftUI.Scene {
        WindowGroup("Godot 3D", id: "gdrk-extra-volume", for: VolumeSessionKey.self) { $key in
            if let key, let record = Bridge.volumeWindows[key.id], record.generation == key.generation {
                VolumeWindowContent(record: record)
            } else {
                StaleVolumeWindow()
            }
        }
        .windowStyle(.volumetric)
        .windowResizability(.contentSize)
        .restorationBehavior(.disabled)
    }
}

class BridgeScene: NSObject, @MainActor UIHostingSceneDelegate {
    static var rootScene: some SwiftUI.Scene {
        WindowGroup(id: ScenePresentationStyle.sharedVolumetric.rawValue) {
            if let record = Bridge.volumeWindows[0] { VolumeWindowContent(record: record) }
        }
        .windowStyle(.volumetric)
        .windowResizability(.contentSize)
        .restorationBehavior(.disabled)
        WindowGroup(id: ScenePresentationStyle.sharedPortal.rawValue) {
            PortalRealityView(root: Bridge.root.value, delegate: Bridge.delegate)
            .overlay{GodotViewControllerRepresentable()}
            .modifier(GodotSceneVisibilityBridge())
        }
        .restorationBehavior(.disabled)
        ImmersiveSpace(id: ScenePresentationStyle.immersive.rawValue) {
            ImmersiveRealityView(root: Bridge.root.value, delegate: Bridge.delegate)
            .overlay{GodotViewControllerRepresentable()}
            .modifier(GodotSceneVisibilityBridge())
        }
        .immersionStyle(selection: Binding(get: {
            switch Bridge.immersionStyle {
            case .mixed: return .mixed
            case .full: return .full
            case .progressive: return .progressive
            }
        }, set: { _ in }), in: .mixed, .full, .progressive)
        .restorationBehavior(.disabled)

    }

    public func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
    }

    public func sceneDidBecomeActive(_ scene: UIScene) {
        Bridge.resumeGodotAudioAfterActivatingSession()
    }

    public func sceneWillResignActive(_ scene: UIScene) {
        let sel = Selector(("sceneWillResignActive:"))
        if let appDelegate = UIApplication.shared.delegate,
           appDelegate.responds(to: sel) {
            appDelegate.perform(sel, with: scene)
        }
    }

}

#else

struct DesktopRealityView : View {
    let root: RealityKit.Entity
    let delegate: GDRKBridgeDelegate?

    public static let light = createBlackIBLEntity()

    public var body: some View {
        GeometryReader{ proxy in
            RealityView(make: { content in
                content.add(self.root)
            }, update: { content in
                self.delegate?.onWindowResized(simd_float2(Float(proxy.size.width), Float(proxy.size.height)))
            })
            .installGestures(delegate: self.delegate, root: self.root, size: proxy.size)
//            .allowsHitTesting(false)
            .background(.black)
        }
    }

    static func createBlackEnvironmentResource() -> RealityKit.EnvironmentResource? {
        var srgbData = [UInt32](repeating: 0x0, count: 1)
        let cgImage = srgbData.withUnsafeMutableBytes { ptr in
            let ctx = CGContext(
                data: ptr.baseAddress,
                width: 1,
                height: 1,
                bitsPerComponent: 8,
                bytesPerRow: 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue +
                    CGImageAlphaInfo.premultipliedFirst.rawValue
                )!
            return ctx.makeImage()
        }

        guard let cgImage else {
            return nil
        }

        return try? RealityKit.EnvironmentResource(equirectangular: cgImage)
    }

    static func createBlackIBLEntity() -> RealityKit.Entity? {
        if let blackEnvResource = createBlackEnvironmentResource() {
            return RealityKit.Entity(components: [ImageBasedLightComponent(source: .single(blackEnvResource))])
        } else {
            return nil
        }
    }
}

#endif

public class Bridge {
    @MainActor static public var delegate: GDRKBridgeDelegate? = nil
    @MainActor static var root = Entity.initAndMaterialize()

    @MainActor static var blockingAsyncTaskCount = 0
    @MainActor static var sceneVisible = false

    @MainActor static var presentationStyle = ScenePresentationStyle.sharedVolumetric
    @MainActor static var immersionStyle = SceneImmersionStyle.full

    #if !os(macOS)
    @MainActor static var originalScene: UIWindowScene? = nil
    @MainActor static var originalViewController: UIViewController? = nil
    @MainActor static var bootSplashImage: UIImage? = nil
    @MainActor static var bootSplashBgColor: UIColor = .black
    @MainActor static var audioInterruptionObserver: Any? = nil
    #endif

    #if !os(macOS)
    @MainActor static var volumeWindows: [UInt64: VolumeWindowRecord] = [:]
    @MainActor private static var operationDriver: GodotViewController?
    public static func setVolumeRequestsPending(_ pending: Bool) {
        MainActor.assumeIsolated {
            if pending {
                if operationDriver == nil { operationDriver = GodotViewController() }
                operationDriver?.startRendering()
            } else {
                operationDriver?.stopRendering()
                operationDriver = nil
            }
        }
    }
    public static func isAccessoryTrackingSupported() -> Bool { AccessoryTrackingProvider.isSupported }
    public static func stopAccessoryTracking() { MainActor.assumeIsolated { SharedAccessoryTracking.shared.stop() } }
    public static func registerVolumeWindow(_ root: Entity, _ delegate: GDRKBridgeDelegate, _ id: UInt64, _ generation: UInt64) {
        assumeMainActor(root, delegate, id, generation) { root, delegate, id, generation in
            volumeWindows[id] = VolumeWindowRecord(root: root.value, delegate: delegate, id: id, generation: generation)
        }
    }
    public static func configureVolumeWindow(_ id: UInt64, _ generation: UInt64, _ title: String,
        _ config: GDRKVolumeConfiguration) {
        MainActor.assumeIsolated {
            guard let record = volumeWindows[id], record.generation == generation else { return }
            record.title = title
            // Initial size is an opening preference. Never resize a live volume when it changes.
            if record.scene == nil { record.initial = config.initial_size }
            if config.resize_mode == 1 {
                for axis in 0..<3 {
                    if record.resizeMode != 1 || record.fixedSize[axis] == 0 {
                        record.fixedSize[axis] = record.scene == nil && config.initial_size[axis] > 0
                            ? config.initial_size[axis] : config.actual_size[axis]
                    }
                    if record.fixedSize[axis] > 0 {
                        record.fixedSize[axis] = max(record.fixedSize[axis], config.minimum_size[axis])
                        if config.maximum_size[axis] > 0 {
                            record.fixedSize[axis] = min(record.fixedSize[axis], config.maximum_size[axis])
                        }
                    }
                }
            }
            record.minimum = config.minimum_size; record.maximum = config.maximum_size
            record.resizeMode = config.resize_mode; record.baseplate = config.baseplate_visibility
            record.applyGeometry()
        }
    }
    public static func reopenVolumeWindow(_ id: UInt64, _ generation: UInt64) {
        assumeMainActor(id, generation) { id, generation in
            guard let record = volumeWindows[id], record.generation == generation else { return }
            record.open()
        }
    }
    public static func closeVolumeWindow(_ id: UInt64, _ generation: UInt64) {
        assumeMainActor(id, generation) { id, generation in
            guard let record = volumeWindows[id], record.generation == generation else { return }
            record.close()
        }
    }
    public static func forgetVolumeWindow(_ id: UInt64, _ generation: UInt64) {
        assumeMainActor(id, generation) { id, generation in
            if volumeWindows[id]?.generation == generation { volumeWindows.removeValue(forKey: id) }
        }
    }
    #endif

    public init() {}

    public static func initialize(delegate: GDRKBridgeDelegate) {
        assumeMainActor(delegate) { delegate in
            Self.delegate = delegate
            #if !os(macOS)
            Godot2DWindowRequests.install()
            volumeWindows[0] = VolumeWindowRecord(root: Self.root.value, delegate: delegate, id: 0, generation: 0)
            volumeWindows[0]?.opening = true
            #endif
            _ = Self.root

            let settings = delegate.getExtensionSettings()

            Self.presentationStyle = {
                switch settings.presentationStyle {
                case .immersive: return .immersive
                case .volumetricPortal: return .sharedPortal
                case .volumetricWindow: return .sharedVolumetric
                @unknown default: return .sharedVolumetric
                }
            }()

            Self.immersionStyle = {
                switch settings.immersionStyle {
                case .mixed: return .mixed
                case .full: return .full
                case .progressive: return .progressive
                @unknown default: return .full
                }
            }()
        }

#if os(macOS)
        assumeMainActor(self, delegate){ s, delegate in
            let rkViewHost =
                NSHostingController(
                    rootView: DesktopRealityView(root: s.root.value,
                                                 delegate: Bridge.delegate)
                )
            if let window = delegate.getDisplayServerWindow() {
                if let contentView = window.contentView {
                    contentView.addSubview(rkViewHost.view)
                    rkViewHost.view.setFrameSize(contentView.frame.size)
                    rkViewHost.view.translatesAutoresizingMaskIntoConstraints = false;

                    let top = rkViewHost.view.topAnchor.constraint(equalTo: contentView.topAnchor)
                    let leading = rkViewHost.view.leadingAnchor.constraint(equalTo: contentView.leadingAnchor)
                    let trailing = rkViewHost.view.trailingAnchor.constraint(equalTo: contentView.trailingAnchor)
                    let bottom = rkViewHost.view.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)

                    NSLayoutConstraint.activate([ top, leading, trailing, bottom ]);
                }
            } else {
                print("no window or no content view controller!")
            }

            Bridge.sceneVisible = true
        }

#else
        assumeMainActor(delegate) { delegate in
            guard let originalScene = UIApplication.shared.connectedScenes.first as? UIWindowScene else {
                print("No open sessions in application!")
                return
            }

            // We need this to keep a hard reference to the original scene somewhere so it doesn't get
            // deallocated when the UIScene is destroyed
            Self.originalScene = originalScene
            Self.originalViewController = delegate.getDisplayServerViewController()
            Self.bootSplashImage = delegate.getBootSplashImage()
            Self.bootSplashBgColor = delegate.getBootSplashBgColor()

            // The scene transition below may interrupt the AVAudioSession.
            // Godot's own interruption handler calls on_focus_in() when the
            // interruption ends, but we also reactivate the session ourselves
            // as a safety net. The primary audio restart after the original
            // scene is destroyed happens in destroyOriginalScene().
            Self.audioInterruptionObserver = NotificationCenter.default.addObserver(
                forName: AVAudioSession.interruptionNotification,
                object: AVAudioSession.sharedInstance(),
                queue: nil
            ) { notification in
                guard let info = notification.userInfo,
                      let typeValue = info[AVAudioSessionInterruptionTypeKey] as? UInt,
                      let type = AVAudioSession.InterruptionType(rawValue: typeValue),
                      type == .ended else {
                    return
                }
                do {
                    try AVAudioSession.sharedInstance().setActive(true)
                } catch {
                    print("GodotRealityKit: failed to reactivate audio session after interruption: \(error)")
                }
            }

            // Set the original godot plain window to a simple view showing just the loading screen
            // Setting the root view controller here secretly unlinks the display link, stopping the game loop
            originalScene.keyWindow?.rootViewController = LoadingViewController()

            NotificationCenter.default.addObserver(
                forName: Self.relaunchNotification,
                object: nil,
                queue: .main
            ) { _ in
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        Bridge.reattachAfterRelaunch()
                    }
                }
            }
        }
#endif
    }

    public static func getRoot() -> Entity {
        MainActor.assumeIsolated{ Self.root }
    }

    public static func isSceneVisible() -> Bool {
        MainActor.assumeIsolated{ Self.sceneVisible }
    }

#if !os(macOS)
    public static let relaunchNotification = Notification.Name("GDRKRendererRelaunchDetected")

    @MainActor
    static func reattachAfterRelaunch() {
        let windowScenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let candidate = windowScenes.first { scene in
            guard !(scene.delegate is BridgeScene) else { return false }
            guard let root = scene.keyWindow?.rootViewController else { return false }
            return !(root is LoadingViewController)
        }

        guard let newScene = candidate else {
            print("GodotRealityKit: relaunch guard could not find a godot UIWindowScene to reattach")
            return
        }

        Self.originalScene = newScene
        newScene.keyWindow?.rootViewController = LoadingViewController()
    }

    static func resumeGodotAudioAfterActivatingSession() {
        let sel = Selector(("sceneDidBecomeActive:"))
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try AVAudioSession.sharedInstance().setActive(true)
            } catch {
                print("GodotRealityKit: failed to activate audio session before resuming Godot audio: \(error)")
            }
            DispatchQueue.main.async {
                guard let appDelegate = UIApplication.shared.delegate,
                      appDelegate.responds(to: sel) else {
                    return
                }
                let activeScene = UIApplication.shared.connectedScenes.first {
                    $0.activationState == .foregroundActive
                } ?? UIApplication.shared.connectedScenes.first
                appDelegate.perform(sel, with: activeScene)
            }
        }
    }
#endif
}
