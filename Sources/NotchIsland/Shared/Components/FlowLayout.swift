import SwiftUI

/// Раскладка «потоком»: слева направо, не влезло — на следующую строку. Каждый элемент своего
/// размера (не шире maxItemWidth), строка высотой с самый высокий элемент, элементы прижаты к верху
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    var maxItemWidth: CGFloat = .infinity

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? maxItemWidth
        let rows = arrange(width: width, subviews: subviews)
        return CGSize(width: width, height: rows.last.map { $0.y + $0.height } ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for row in arrange(width: bounds.width, subviews: subviews) {
            for item in row.items {
                subviews[item.index].place(at: CGPoint(x: bounds.minX + item.x, y: bounds.minY + row.y),
                                           proposal: ProposedViewSize(item.size))
            }
        }
    }

    private struct Row {
        var items: [(index: Int, x: CGFloat, size: CGSize)] = []
        var y: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = []
        var row = Row()
        var x: CGFloat = 0
        for (i, view) in subviews.enumerated() {
            var size = view.sizeThatFits(ProposedViewSize(width: min(width, maxItemWidth), height: nil))
            size.width = min(size.width, width)
            if x > 0 && x + size.width > width {
                let y = row.y + row.height + spacing
                rows.append(row)
                row = Row(y: y)
                x = 0
            }
            row.items.append((i, x, size))
            row.height = max(row.height, size.height)
            x += size.width + spacing
        }
        if !row.items.isEmpty { rows.append(row) }
        return rows
    }
}
