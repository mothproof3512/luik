import AppKit
import QuartzCore

/// How the panel itself arrives for a "Screens and consoles" scheme: instead of the plain slide
/// from the top, the panel's layer is scaled, tilted, flashed or opened like a CRT. Core
/// Animation on the content view, so the terminal view moves with everything else.
enum ThemeEntrance {
    /// Duration of the entrance for a scheme; nil = the scheme has none (plain slide).
    static func duration(for theme: LuikTheme) -> TimeInterval? {
        switch theme.id {
        case "screen-bridge": return 0.55
        case "screen-chevron": return 0.75
        case "screen-rebel": return 0.6
        case "screen-wopr": return 0.7
        case "screen-gibson": return 0.65
        case "screen-rain": return 0.9
        case "screen-section9": return 0.6
        case "screen-grid": return 0.8
        case "screen-november": return 0.55
        case "screen-basement": return 0.9
        case "screen-incubator": return 0.5
        default: return nil
        }
    }

    /// Scale about a pivot given in layer coordinates (bottom-left origin, as AppKit layers).
    private static func scale(x sx: CGFloat, y sy: CGFloat, pivot: CGPoint) -> CATransform3D {
        var t = CATransform3DMakeTranslation(pivot.x, pivot.y, 0)
        t = CATransform3DScale(t, sx, sy, 1)
        t = CATransform3DTranslate(t, -pivot.x, -pivot.y, 0)
        return t
    }

    /// Rotation about the x axis with perspective, pivot at the top edge.
    private static func tilt(angle: CGFloat, size: CGSize) -> CATransform3D {
        var perspective = CATransform3DIdentity
        perspective.m34 = -1 / 900
        var t = CATransform3DTranslate(perspective, size.width / 2, size.height, 0)
        t = CATransform3DRotate(t, angle, 1, 0, 0)
        t = CATransform3DTranslate(t, -size.width / 2, -size.height, 0)
        return t
    }

    private static func basic(_ keyPath: String, from: Any, to: Any, duration: TimeInterval, timing: CAMediaTimingFunctionName = .easeOut) -> CABasicAnimation {
        let animation = CABasicAnimation(keyPath: keyPath)
        animation.fromValue = from
        animation.toValue = to
        animation.duration = duration
        animation.timingFunction = CAMediaTimingFunction(name: timing)
        return animation
    }

    private static func spring(_ keyPath: String, from: Any, to: Any, damping: CGFloat, duration: TimeInterval) -> CASpringAnimation {
        let animation = CASpringAnimation(keyPath: keyPath)
        animation.fromValue = from
        animation.toValue = to
        animation.damping = damping
        animation.stiffness = 220
        animation.mass = 1
        animation.initialVelocity = 0
        animation.duration = duration
        return animation
    }

    private static func keyframes(_ keyPath: String, values: [Any], times: [NSNumber], duration: TimeInterval) -> CAKeyframeAnimation {
        let animation = CAKeyframeAnimation(keyPath: keyPath)
        animation.values = values
        animation.keyTimes = times
        animation.duration = duration
        animation.calculationMode = .discrete
        return animation
    }

    /// Plays the entrance on `layer` (the panel's content view, already at its final frame).
    /// Returns false when the scheme has no entrance. `completion` runs on the main thread.
    @discardableResult
    static func play(on layer: CALayer, size: CGSize, theme: LuikTheme, completion: @escaping () -> Void) -> Bool {
        guard let duration = duration(for: theme) else { return false }
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let topCenter = CGPoint(x: size.width / 2, y: size.height)
        var animations: [CAAnimation] = []

        switch theme.id {
        case "screen-bridge":
            // Slides in from the left, the way a console panel sweeps into view.
            animations.append(basic("transform", from: CATransform3DMakeTranslation(-size.width, 0, 0), to: CATransform3DIdentity, duration: duration, timing: .easeOut))
            animations.append(basic("opacity", from: 0.4, to: 1, duration: duration * 0.6))
        case "screen-chevron":
            // Opens from a point in the centre, like stepping through the horizon.
            animations.append(spring("transform", from: scale(x: 0.05, y: 0.05, pivot: center), to: CATransform3DIdentity, damping: 14, duration: duration))
            animations.append(basic("opacity", from: 0, to: 1, duration: duration * 0.4))
        case "screen-rebel":
            // Jumps in: stretched long and thin, then snaps to size.
            let jump = keyframes("transform",
                                 values: [scale(x: 1.6, y: 0.02, pivot: center), scale(x: 1.2, y: 0.35, pivot: center), CATransform3DIdentity],
                                 times: [0, 0.35, 1], duration: duration)
            jump.calculationMode = .linear
            jump.timingFunctions = [CAMediaTimingFunction(name: .easeIn), CAMediaTimingFunction(name: .easeOut)]
            animations.append(jump)
            animations.append(basic("opacity", from: 0, to: 1, duration: duration * 0.3))
        case "screen-wopr", "screen-basement":
            // CRT switching on: a thin bright line that opens vertically, with a flicker.
            animations.append(basic("transform", from: scale(x: 1.0, y: 0.01, pivot: center), to: CATransform3DIdentity, duration: duration * 0.55, timing: .easeOut))
            animations.append(keyframes("opacity", values: [1, 0.55, 1, 0.7, 1], times: [0, 0.6, 0.7, 0.8, 0.9], duration: duration))
        case "screen-gibson":
            // Swings open from the left edge, like a door into the mainframe.
            var perspective = CATransform3DIdentity
            perspective.m34 = -1 / 1200
            let closed = CATransform3DRotate(perspective, -.pi / 2.2, 0, 1, 0)
            animations.append(basic("transform", from: closed, to: CATransform3DIdentity, duration: duration, timing: .easeOut))
            animations.append(basic("opacity", from: 0.2, to: 1, duration: duration * 0.5))
        case "screen-rain":
            // The rain falls first; the panel fades in underneath it.
            animations.append(basic("opacity", from: 0, to: 1, duration: duration, timing: .easeIn))
        case "screen-section9":
            // Unrolls from the top edge, the scan band leading.
            animations.append(basic("transform", from: scale(x: 1, y: 0.01, pivot: topCenter), to: CATransform3DIdentity, duration: duration, timing: .easeInEaseOut))
        case "screen-grid":
            // Tilts up from the floor into the screen plane.
            animations.append(basic("transform", from: tilt(angle: -.pi / 2.3, size: size), to: CATransform3DIdentity, duration: duration, timing: .easeOut))
            animations.append(basic("opacity", from: 0.3, to: 1, duration: duration * 0.7))
        case "screen-november":
            // Hard cuts: the signal breaks through in three flashes.
            animations.append(keyframes("opacity", values: [0, 1, 0, 1, 0.2, 1], times: [0, 0.15, 0.3, 0.45, 0.6, 0.75], duration: duration))
        case "screen-incubator":
            // Pops in with a small overshoot.
            animations.append(spring("transform", from: scale(x: 0.85, y: 0.85, pivot: center), to: CATransform3DIdentity, damping: 11, duration: duration))
            animations.append(basic("opacity", from: 0, to: 1, duration: duration * 0.4))
        default:
            return false
        }

        CATransaction.begin()
        CATransaction.setCompletionBlock {
            layer.removeAnimation(forKey: "luik-entrance")
            DispatchQueue.main.async(execute: completion)
        }
        let group = CAAnimationGroup()
        group.animations = animations
        group.duration = duration
        group.fillMode = .backwards
        group.isRemovedOnCompletion = true
        layer.add(group, forKey: "luik-entrance")
        CATransaction.commit()
        return true
    }
}
