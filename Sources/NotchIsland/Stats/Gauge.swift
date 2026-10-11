import SwiftUI

/// Шкала статистики: график за минуту или полоска заполнения
enum Gauge {
    /// capacity — сколько точек помещается по ширине (график «едет» справа налево)
    case graph([Double], capacity: Int = SystemStats.historyLength)
    case bar(Double)
    var isBar: Bool { if case .bar = self { return true } else { return false } }
}

struct GaugeView: View {
    let gauge: Gauge
    let color: Color

    var body: some View {
        switch gauge {
        case .graph(let v, let cap):
            ZStack {
                Sparkline(values: v, capacity: cap, closed: true)
                    .fill(LinearGradient(colors: [color.opacity(0.35), color.opacity(0)], startPoint: .top, endPoint: .bottom))
                Sparkline(values: v, capacity: cap)
                    .stroke(color, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
            }
        case .bar(let f):
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    // пустая шкала подкрашена своим цветом: «0» отличается от «нет данных» (серый)
                    Capsule().fill(f > 0 ? Color.white.opacity(0.15) : color.opacity(0.35))
                    if f > 0 {
                        Capsule().fill(color).frame(width: max(g.size.height, g.size.width * CGFloat(min(f, 1))))
                    }
                }
            }
        }
    }
}

/// Линия графика; значения прижаты вправо, так что график «едет» справа налево
struct Sparkline: Shape {
    var values: [Double]
    var capacity: Int
    var closed = false   // замкнуть вниз — для заливки под линией

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let vals = Array(values.suffix(capacity))
        guard vals.count > 1, capacity > 1 else { return p }
        let step = rect.width / CGFloat(capacity - 1)
        let x0 = rect.maxX - CGFloat(vals.count - 1) * step
        func point(_ i: Int) -> CGPoint {
            CGPoint(x: x0 + CGFloat(i) * step,
                    y: rect.maxY - CGFloat(min(max(vals[i], 0), 1)) * rect.height)
        }
        p.move(to: point(0))
        for i in 1..<vals.count { p.addLine(to: point(i)) }
        if closed {
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            p.addLine(to: CGPoint(x: x0, y: rect.maxY))
            p.closeSubpath()
        }
        return p
    }
}
