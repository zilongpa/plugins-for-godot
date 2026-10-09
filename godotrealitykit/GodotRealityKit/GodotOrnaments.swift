// Copyright © 2026. Licensed under the MIT license; see LICENSE.

#if os(visionOS)
import SwiftUI
import UIKit
import GameController

@MainActor @Observable
final class GodotOrnamentRecord {
    let windowID: UInt64
    let volumeID: UInt64
    var size: CGSize
    var clearanceMeters: CGFloat?

    var clearancePoints: CGFloat { hypot(size.width, size.height) / 2 + 24 }

    init(windowID: UInt64, volumeID: UInt64, size: SIMD2<Float>) {
        self.windowID = windowID
        self.volumeID = volumeID
        self.size = CGSize(width: CGFloat(size.x), height: CGFloat(size.y))
    }
}

/// Logical panel ownership survives a volume's native scene being closed and reopened.
@MainActor @Observable
final class GodotOrnaments {
    static let shared = GodotOrnaments()
    private(set) var records: [UInt64: GodotOrnamentRecord] = [:]
    private var resizeObserver: NSObjectProtocol?

    func record(for volumeID: UInt64) -> GodotOrnamentRecord? {
        records.values.first { $0.volumeID == volumeID }
    }

    func install() {
        guard resizeObserver == nil else { return }
        resizeObserver = NotificationCenter.default.addObserver(
            forName: Notification.Name("org.godotengine.visionos.embeddedWindowSize"), object: nil, queue: .main
        ) { notification in
            guard let id = notification.object as? UInt64,
                  let width = notification.userInfo?["width"] as? Double,
                  let height = notification.userInfo?["height"] as? Double,
                  width.isFinite, height.isFinite, width > 0, height > 0 else { return }
            // UIKit layout can run during a SwiftUI update. Apply the new frame on the next turn.
            Task { @MainActor in
                guard let record = self.records[id] else { return }
                let size = CGSize(width: width, height: height)
                if record.size != size {
                    NSLog("[GDRK Ornament] size window=%llu %.1fx%.1f -> %.1fx%.1f pt", id,
                          record.size.width, record.size.height, size.width, size.height)
                    record.size = size
                }
            }
        }
    }

    /// Returns true when the request belongs to an ornament, including a rejected request.
    func openIfRequested(_ id: UInt64) -> Bool {
        guard let delegate = Bridge.delegate else { return false }
        let volumeID = delegate.get2DWindowOrnamentVolume(id)
        if volumeID == -1 { return false }
        func fail(_ message: String) -> Bool {
            message.withCString { delegate.on2DWindowFailed(id, $0) }
            return true
        }
        guard volumeID >= 0 else { return fail("Ornament volume ID must be a nonnegative integer") }
        guard let controllerType = NSClassFromString("GDTViewController") as? UIViewController.Type,
              controllerType.instancesRespond(to: NSSelectorFromString("setGodotEmbeddedWindow:")) else {
            return fail("Ornaments require the Godot embedded-window hosting patch and a rebuilt export template")
        }
        guard Bridge.volumeWindows[UInt64(volumeID)] != nil else {
            return fail("The ornament's volume does not exist; create the volume before showing the panel")
        }
        if records[id] != nil { return true }
        guard record(for: UInt64(volumeID)) == nil else {
            return fail("This volume already has an ornament; put related controls in the same panel")
        }
        delegate.set2DWindowNativeOpen(id, false)
        let record = GodotOrnamentRecord(windowID: id, volumeID: UInt64(volumeID),
            size: delegate.get2DWindowSizePoints(id))
        records[id] = record
        NSLog("[GDRK Ornament] attached window=%llu volume=%lld size=%.1fx%.1f pt",
              id, volumeID, record.size.width, record.size.height)
        return true
    }

    func remove(_ id: UInt64) {
        guard records.removeValue(forKey: id) != nil else { return }
        Bridge.delegate?.set2DWindowNativeOpen(id, false)
        NSLog("[GDRK Ornament] detached window=%llu", id)
    }
}

private struct GodotOrnamentController: UIViewControllerRepresentable {
    let record: GodotOrnamentRecord

    @MainActor final class Coordinator {
        let record: GodotOrnamentRecord
        init(record: GodotOrnamentRecord) { self.record = record }

        func stop() {
            NSLog("[GDRK Ornament] dismantle window=%llu", record.windowID)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(record: record) }

    func makeUIViewController(context: Context) -> UIViewController {
        guard let controllerType = NSClassFromString("GDTViewController") as? UIViewController.Type else {
            return UIViewController()
        }
        let controller = controllerType.init(nibName: nil, bundle: nil)
        controller.setValue(NSNumber(value: record.windowID), forKey: "godotWindowID")
        controller.setValue(true, forKey: "godotEmbeddedWindow")
        // Keep the standard gaze-and-select path used by other 2D controls.
        for interaction in controller.view.interactions where interaction is GCEventInteraction {
            controller.view.removeInteraction(interaction)
        }
        return controller
    }

    func updateUIViewController(_ controller: UIViewController, context: Context) {}

    static func dismantleUIViewController(_ controller: UIViewController, coordinator: Coordinator) {
        coordinator.stop()
        controller.perform(NSSelectorFromString("godotDetachEmbeddedWindow"))
    }
}

private struct GodotOrnamentPanel: View {
    let record: GodotOrnamentRecord
    @Environment(\.physicalMetrics) private var metrics

    private var clearanceMeters: CGFloat {
        // Measure in the ornament's environment: the system can scale ornaments
        // independently of the volume. A half diagonal also allows for yaw.
        let meters = metrics.worldScalingCompensation(.unscaled).convert(record.clearancePoints, to: .meters)
        return ceil(meters * 1000) / 1000
    }

    var body: some View {
        ZStack {
            GodotOrnamentController(record: record)
                .id(record.windowID)
                .onAppear {
                    NSLog("[GDRK Ornament] appear window=%llu size=%.1fx%.1f pt", record.windowID,
                          record.size.width, record.size.height)
                    Bridge.delegate?.set2DWindowNativeOpen(record.windowID, true)
                }
                .onDisappear {
                    NSLog("[GDRK Ornament] disappear window=%llu", record.windowID)
                    Bridge.delegate?.set2DWindowNativeOpen(record.windowID, false)
                }
        }
        .frame(width: record.size.width, height: record.size.height)
        .glassBackgroundEffect()
        .onChange(of: clearanceMeters, initial: true) { _, clearance in
            guard clearance.isFinite, clearance > 0 else { return }
            record.clearanceMeters = clearance
        }
    }
}

struct GodotOrnamentModifier: ViewModifier {
    let volumeID: UInt64
    @Environment(\.physicalMetrics) private var metrics
    @State private var minimumHorizontalExtent: CGFloat = 0

    func body(content: Content) -> some View {
        let record = GodotOrnaments.shared.record(for: volumeID)
        let radius = record?.clearancePoints ?? 0
        let fallback = metrics.worldScalingCompensation(.unscaled).convert(radius, to: .meters)
        let clearance = record?.clearanceMeters ?? fallback
        let front = minimumHorizontalExtent > 0 ? 1 + clearance / minimumHorizontalExtent : 1
        // Move the scene attachment itself outside the volume. A visual offset
        // can escape the ornament's measured bounds and crop its UIKit content.
        // Use the smaller horizontal extent so clearance also covers side views.
        return content
            .onGeometryChange3D(for: CGFloat.self) { proxy in
                metrics.worldScalingCompensation(.unscaled).convert(
                    CGFloat(min(proxy.size.width, proxy.size.depth)), to: .meters)
            } action: { extent in
                if extent.isFinite, extent > 0 { minimumHorizontalExtent = extent }
            }
            .ornament(visibility: record == nil || minimumHorizontalExtent <= 0 ? .hidden : .visible,
                      attachmentAnchor: .scene(UnitPoint3D(x: 0.5, y: 1, z: front)),
                      contentAlignment: .center) {
                if let record {
                    GodotOrnamentPanel(record: record)
                        .id(record.windowID)
                }
            }
    }
}
#endif
