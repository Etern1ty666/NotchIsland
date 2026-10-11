import SwiftUI

/// Сверху — вогнутые «ушки», как у настоящего выреза, снизу — обычные скругления.
/// Обе величины анимируются (работает с macOS 13).
struct IslandShape: Shape {
    var top: CGFloat
    var bottom: CGFloat
    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(top, bottom) }
        set { top = newValue.first; bottom = newValue.second }
    }

    func path(in rect: CGRect) -> Path {
        let t = max(0, min(top, rect.width / 4, rect.height / 2))
        let b = max(0, min(bottom, (rect.width - 2 * t) / 2, rect.height - t))
        let k: CGFloat = 0.5523   // контрольная точка кривой Безье для четверти окружности
        let l = rect.minX + t, r = rect.maxX - t   // боковые стенки «тела»
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addCurve(to: CGPoint(x: l, y: rect.minY + t),
                   control1: CGPoint(x: rect.minX + k * t, y: rect.minY),
                   control2: CGPoint(x: l, y: rect.minY + t - k * t))
        p.addLine(to: CGPoint(x: l, y: rect.maxY - b))
        p.addCurve(to: CGPoint(x: l + b, y: rect.maxY),
                   control1: CGPoint(x: l, y: rect.maxY - b + k * b),
                   control2: CGPoint(x: l + b - k * b, y: rect.maxY))
        p.addLine(to: CGPoint(x: r - b, y: rect.maxY))
        p.addCurve(to: CGPoint(x: r, y: rect.maxY - b),
                   control1: CGPoint(x: r - b + k * b, y: rect.maxY),
                   control2: CGPoint(x: r, y: rect.maxY - b + k * b))
        p.addLine(to: CGPoint(x: r, y: rect.minY + t))
        p.addCurve(to: CGPoint(x: rect.maxX, y: rect.minY),
                   control1: CGPoint(x: r, y: rect.minY + t - k * t),
                   control2: CGPoint(x: rect.maxX - k * t, y: rect.minY))
        p.closeSubpath()
        return p
    }
}
