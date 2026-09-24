import Foundation

#if os(visionOS)
import UIKit

@MainActor
private final class HoverTarget {
    weak var controller: UIViewController?
    let layer: UIHoverEffectLayer
    var pixels: CGRect = .zero
    var radii: [CGFloat] = [0, 0, 0, 0]
    var opacity: CGFloat = 1
    var effect: Int32 = 0
    var shape: Int32 = 0
    private var lastFrame: CGRect?
    private var lastRadii: [CGFloat] = []
    private var lastOpacity: CGFloat = -1
    private var lastEffect: Int32 = -1
    private var lastShape: Int32 = -1

    init(controller: UIViewController) {
        self.controller = controller
        layer = UIHoverEffectLayer(containerView: controller.view,
                                   style: UIHoverStyle(effect: .highlight))
    }

    func refresh() {
        guard let view = controller?.viewIfLoaded,
              let window = view.window,
              window.windowScene?.activationState == .foregroundActive else {
            layer.removeFromSuperlayer()
            lastFrame = nil
            return
        }
        let scale = view.contentScaleFactor
        guard scale > 0 else {
            layer.removeFromSuperlayer()
            lastFrame = nil
            return
        }
        let frame = CGRect(x: pixels.minX / scale, y: pixels.minY / scale,
                           width: pixels.width / scale, height: pixels.height / scale)
        guard frame.width > 0 && frame.height > 0 else {
            layer.removeFromSuperlayer()
            lastFrame = nil
            return
        }
        if layer.superlayer === view.layer,
           lastFrame == frame,
           lastRadii == radii,
           lastOpacity == opacity,
           lastEffect == effect,
           lastShape == shape {
            return
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if layer.superlayer !== view.layer {
            layer.containerView = view
            view.layer.addSublayer(layer)
        }
        layer.frame = frame
        layer.opacity = Float(max(0, min(1, opacity)))
        let hoverShape: UIShape
        switch shape {
        case 1: hoverShape = .rect
        case 2: hoverShape = .capsule
        case 3: hoverShape = .circle
        default:
            let path = Self.roundedPath(size: frame.size, radii: radii.map { $0 / scale })
            hoverShape = .path(path)
        }
        switch effect {
        case 1: layer.hoverStyle = UIHoverStyle(effect: .automatic, shape: hoverShape)
        case 2: layer.hoverStyle = UIHoverStyle(effect: .lift, shape: hoverShape)
        default: layer.hoverStyle = UIHoverStyle(effect: .highlight, shape: hoverShape)
        }
        CATransaction.commit()
        lastFrame = frame
        lastRadii = radii
        lastOpacity = opacity
        lastEffect = effect
        lastShape = shape
    }

    private static func roundedPath(size: CGSize, radii: [CGFloat]) -> UIBezierPath {
        let path = UIBezierPath()
        let half = min(size.width, size.height) / 2
        let tl = min(max(0, radii[0]), half)
        let tr = min(max(0, radii[1]), half)
        let br = min(max(0, radii[2]), half)
        let bl = min(max(0, radii[3]), half)
        path.move(to: CGPoint(x: tl, y: 0))
        path.addLine(to: CGPoint(x: size.width - tr, y: 0))
        path.addQuadCurve(to: CGPoint(x: size.width, y: tr), controlPoint: CGPoint(x: size.width, y: 0))
        path.addLine(to: CGPoint(x: size.width, y: size.height - br))
        path.addQuadCurve(to: CGPoint(x: size.width - br, y: size.height), controlPoint: CGPoint(x: size.width, y: size.height))
        path.addLine(to: CGPoint(x: bl, y: size.height))
        path.addQuadCurve(to: CGPoint(x: 0, y: size.height - bl), controlPoint: CGPoint(x: 0, y: size.height))
        path.addLine(to: CGPoint(x: 0, y: tl))
        path.addQuadCurve(to: CGPoint(x: tl, y: 0), controlPoint: CGPoint(x: 0, y: 0))
        path.close()
        return path
    }
}

@MainActor
private final class HoverRegistry: NSObject {
    static let shared = HoverRegistry()
    private var targets: [UInt64: HoverTarget] = [:]
    private var timer: CADisplayLink?

    func update(id: UInt64, controller: UIViewController, rect: CGRect,
                radii: [CGFloat], opacity: CGFloat, effect: Int32, shape: Int32) {
        let target: HoverTarget
        if let old = targets[id], old.controller === controller {
            target = old
        } else {
            targets[id]?.layer.removeFromSuperlayer()
            target = HoverTarget(controller: controller)
            targets[id] = target
        }
        target.pixels = rect
        target.radii = radii
        target.opacity = opacity
        target.effect = effect
        target.shape = shape
        target.refresh()
        if timer == nil {
            timer = CADisplayLink(target: self, selector: #selector(refresh))
            timer?.preferredFramesPerSecond = 30
            timer?.add(to: .main, forMode: .common)
        }
    }

    @objc private func refresh() {
        for (id, target) in Array(targets) {
            if target.controller == nil {
                remove(id: id)
            } else {
                target.refresh()
            }
        }
    }

    func remove(id: UInt64) {
        targets.removeValue(forKey: id)?.layer.removeFromSuperlayer()
        if targets.isEmpty {
            timer?.invalidate()
            timer = nil
        }
    }
}
#endif

@_cdecl("godotvisionos_hover_update")
public func godotvisionosHoverUpdate(_ id: UInt64, _ pointer: UnsafeRawPointer,
                                     _ x: Double, _ y: Double, _ width: Double, _ height: Double,
                                     _ topLeft: Double, _ topRight: Double,
                                     _ bottomRight: Double, _ bottomLeft: Double,
                                     _ opacity: Double, _ effect: Int32, _ shape: Int32) {
    #if os(visionOS)
    let controller = Unmanaged<UIViewController>.fromOpaque(pointer).takeUnretainedValue()
    DispatchQueue.main.async { [weak controller] in
        guard let controller else {
            HoverRegistry.shared.remove(id: id)
            return
        }
        HoverRegistry.shared.update(id: id, controller: controller,
                                    rect: CGRect(x: x, y: y, width: width, height: height),
                                    radii: [topLeft, topRight, bottomRight, bottomLeft],
                                    opacity: opacity, effect: effect, shape: shape)
    }
    #endif
}

@_cdecl("godotvisionos_hover_remove")
public func godotvisionosHoverRemove(_ id: UInt64) {
    #if os(visionOS)
    DispatchQueue.main.async {
        HoverRegistry.shared.remove(id: id)
    }
    #endif
}
