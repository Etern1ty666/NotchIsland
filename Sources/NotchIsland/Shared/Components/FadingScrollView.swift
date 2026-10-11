import SwiftUI

/// Прокрутка без полосы: пока ниже есть ещё содержимое, нижний край растворяется
/// и висит стрелка вниз — по клику прокручивает до конца
struct FadingScrollView<Content: View>: View {
    @ViewBuilder let content: () -> Content
    @State private var moreBelow = false
    @State private var hover = false

    var body: some View {
        GeometryReader { outer in
            ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        content()
                        Color.clear.frame(height: 0).id("end")
                    }
                    // где кончается содержимое — читаем изнутри: на macOS настройки (preference)
                    // из ScrollView наружу не доходят
                    .background(GeometryReader { g in
                        let bottom = g.frame(in: .named("fadingScroll")).maxY
                        Color.clear
                            .onAppear { update(bottom, visible: outer.size.height) }
                            .onChange(of: bottom) { update($0, visible: outer.size.height) }
                    })
                }
                .coordinateSpace(name: "fadingScroll")
                // прокрутка только вверх-вниз: вбок страница не уезжает и не пружинит
                .modifier(NoHorizontalBounce())
                // низ растворяется чёрным поверх (остров чёрный): маска заставляла бы перерисовывать
                // всё содержимое отдельным проходом при каждой подсветке под курсором
                .overlay(alignment: .bottom) {
                    LinearGradient(colors: [.black.opacity(0), .black], startPoint: .top, endPoint: .bottom)
                        .frame(height: 36)
                        .opacity(moreBelow ? 1 : 0)
                        .allowsHitTesting(false)
                }
                .overlay(alignment: .bottom) {
                    if moreBelow {
                        Button {
                            withAnimation(.easeInOut(duration: 0.35)) { proxy.scrollTo("end", anchor: .bottom) }
                        } label: {
                            Image(systemName: "chevron.down")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(Color.white.opacity(hover ? 0.9 : 0.6))
                                .frame(width: 34, height: 18)
                                .background(Capsule().fill(Color(white: hover ? 0.24 : 0.17)))
                                .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .onHover { hover = $0 }
                        .help(L("Ниже есть ещё"))
                        .accessibilityLabel(L("Прокрутить вниз"))
                        .transition(.opacity)
                    }
                }
            }
        }
    }

    private func update(_ bottom: CGFloat, visible: CGFloat) {
        let more = bottom > visible + 2
        if more != moreBelow { withAnimation(.easeOut(duration: 0.2)) { moreBelow = more } }
    }
}

/// Пружина прокрутки — только когда содержимое больше окна (macOS 13.3+): не тянется вбок
struct NoHorizontalBounce: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 13.3, *) {
            content.scrollBounceBehavior(.basedOnSize)
        } else {
            content
        }
    }
}
