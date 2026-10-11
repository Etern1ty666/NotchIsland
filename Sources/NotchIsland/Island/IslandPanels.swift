import SwiftUI
import AppKit

/// Остров никогда не забирает фокус клавиатуры: ввода в нём нет, так что фокус
/// остаётся у приложения, в котором работаешь
final class IslandPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    // Без этого macOS сдвигает окно вниз под строку меню -> видна полоска сверху
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

/// SwiftUI в окне, которое никогда не становится главным (остров не забирает фокус): без своей зоны
/// слежения AppKit почти не шлёт ему движения мыши, и наведение (onHover) срабатывает с запозданием.
/// Зона «всегда активна» с движениями мыши — подсветка под курсором появляется сразу
final class TrackingHostingView<Content: View>: NSHostingView<Content> {
    private var area: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let area { removeTrackingArea(area) }
        let a = NSTrackingArea(rect: .zero,
                               options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
                               owner: self, userInfo: nil)
        addTrackingArea(a)
        area = a
    }
}

/// Невидимая «кнопка» поверх свёрнутого острова: клик раскрывает его сразу, без ожидания
final class HitPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

final class HitView: NSView {
    var onClick: (() -> Void)?
    var onHover: (() -> Void)?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) { onClick?() }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero,
                                       options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
                                       owner: self))
    }
    override func mouseEntered(with event: NSEvent) { onHover?() }
    override func mouseMoved(with event: NSEvent) { onHover?() }
    override func mouseExited(with event: NSEvent) { onHover?() }
}
