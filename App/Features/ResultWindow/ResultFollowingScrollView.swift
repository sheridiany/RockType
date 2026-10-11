import AppKit
import SwiftUI

/// Native scrolling keeps the user's reading position while text grows above the bottom.
struct ResultFollowingScrollView<Content: View>: NSViewRepresentable {
    let resetID: UUID?
    let jump: Int
    @Binding var following: Bool
    @ViewBuilder let content: () -> Content
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = LayoutScrollView()
        scroll.onLayout = { [weak coordinator = context.coordinator] in coordinator?.layout() }
        scroll.hasVerticalScroller = true; scroll.drawsBackground = false
        scroll.autohidesScrollers = true
        scroll.documentView = context.coordinator.host
        scroll.contentView.postsBoundsChangedNotifications = true
        context.coordinator.scroll = scroll
        NotificationCenter.default.addObserver(context.coordinator, selector: #selector(Coordinator.scrolled),
            name: NSView.boundsDidChangeNotification, object: scroll.contentView)
        return scroll
    }
    func updateNSView(_ scroll: NSScrollView, context: Context) {
        let coordinator = context.coordinator
        let reset = coordinator.resetID != resetID
        let jumpRequested = coordinator.jump != jump
        coordinator.parent = self; coordinator.resetID = resetID; coordinator.jump = jump
        coordinator.dirty = true
        if reset || jumpRequested { coordinator.atBottom = true }
        coordinator.layout()
    }
    static func dismantleNSView(_ nsView: NSScrollView, coordinator: Coordinator) {
        NotificationCenter.default.removeObserver(coordinator)
    }
    final class LayoutScrollView: NSScrollView {
        var onLayout: (() -> Void)?
        override func layout() { super.layout(); onLayout?() }
    }
    @MainActor final class Coordinator: NSObject {
        var parent: ResultFollowingScrollView
        let host = NSHostingView(rootView: AnyView(EmptyView()))
        weak var scroll: NSScrollView?
        var atBottom = true
        var resetID: UUID?
        var jump = 0
        var layingOut = false
        var width: CGFloat = 0
        var viewportHeight: CGFloat = 0
        var dirty = true
        init(_ parent: ResultFollowingScrollView) { self.parent = parent }
        @objc func scrolled() {
            guard !layingOut, let scroll else { return }
            atBottom = Self.isAtBottom(visible: scroll.documentVisibleRect, documentHeight: host.frame.height)
            if abs(scroll.contentSize.width - width) > 1 { layout() }
            publish()
        }
        static func isAtBottom(visible: CGRect, documentHeight: CGFloat) -> Bool {
            documentHeight - visible.maxY <= 32
        }
        func layout() {
            guard let scroll, scroll.contentSize.width > 0, !layingOut else { return }
            guard dirty || abs(width - scroll.contentSize.width) > 1 || viewportHeight != scroll.contentSize.height else { return }
            dirty = false
            layingOut = true
            defer { layingOut = false }
            width = scroll.contentSize.width
            viewportHeight = scroll.contentSize.height
            host.rootView = AnyView(parent.content().frame(width: width, alignment: .topLeading))
            host.setFrameSize(CGSize(width: width, height: max(1, host.fittingSize.height)))
            host.layoutSubtreeIfNeeded()
            if atBottom {
                host.scroll(CGPoint(x: 0, y: max(0, host.frame.height - scroll.contentSize.height)))
            }
            publish()
        }
        private func publish() {
            let value = atBottom
            Task { @MainActor [weak self] in
                guard let self, self.atBottom == value else { return }
                if self.parent.following != value { self.parent.following = value }
            }
        }
    }
}

struct ResultWindowDragArea: NSViewRepresentable {
    final class Handle: NSView {
        override func mouseDown(with event: NSEvent) { window?.performDrag(with: event) }
    }
    func makeNSView(context: Context) -> Handle { Handle() }
    func updateNSView(_ nsView: Handle, context: Context) {}
}
