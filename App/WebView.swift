import SwiftUI
import WebKit
import MediaPlayer
import AVKit

@MainActor
struct BrowserWebView: UIViewRepresentable {
    let tab: BrowserTab
    var watchPresentation = false
    var leaveWatch: () -> Void = {}
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeUIView(context: Context) -> WKWebView {
        context.coordinator.attach(to: tab.webView)
        configure(tab.webView, coordinator: context.coordinator)
        return tab.webView
    }
    func updateUIView(_ view: WKWebView, context: Context) { configure(view, coordinator: context.coordinator) }
    static func dismantleUIView(_ view: WKWebView, coordinator: Coordinator) { coordinator.detach() }
    private func configure(_ view: WKWebView, coordinator: Coordinator) {
        coordinator.enabled = watchPresentation
        coordinator.leaveWatch = leaveWatch
        coordinator.playerTouch = { point in
            guard view.bounds.width > 0, view.bounds.height > 0 else { return }
            tab.prepareForPlayback()
            tab.run("globalThis.__webkweb?.noteHostTouch({x:\(Double(point.x / view.bounds.width)),y:\(Double(point.y / view.bounds.height))})")
        }
        view.isOpaque = !watchPresentation
        view.backgroundColor = watchPresentation ? .black : .systemBackground
        view.scrollView.backgroundColor = watchPresentation ? .black : .systemBackground
        view.scrollView.contentInsetAdjustmentBehavior = watchPresentation ? .never : .automatic
    }

    @MainActor
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var enabled = false
        var leaveWatch: () -> Void = {}
        var playerTouch: (CGPoint) -> Void = { _ in }
        private weak var webView: WKWebView?
        private lazy var pan = UIPanGestureRecognizer(target: self, action: #selector(swiped(_:)))
        private lazy var touchObserver: PlayerTouchObserver = {
            let observer = PlayerTouchObserver(target: nil, action: nil)
            observer.touched = { [weak self] point in self?.playerTouch(point) }
            return observer
        }()
        func attach(to view: WKWebView) {
            webView = view; pan.delegate = self; pan.cancelsTouchesInView = false
            pan.maximumNumberOfTouches = 1
            view.addGestureRecognizer(pan)
            touchObserver.cancelsTouchesInView = false
            view.addGestureRecognizer(touchObserver)
        }
        func detach() { webView?.removeGestureRecognizer(pan); webView?.removeGestureRecognizer(touchObserver); webView = nil; playerTouch = { _ in }; leaveWatch = {}; enabled = false }
        func gestureRecognizerShouldBegin(_ gesture: UIGestureRecognizer) -> Bool {
            guard enabled, let view = webView, let pan = gesture as? UIPanGestureRecognizer else { return false }
            let velocity = pan.velocity(in: view), point = pan.location(in: view), delta = pan.translation(in: view)
            let startY = point.y - delta.y
            let videoHeight = min(view.bounds.width * 9 / 16, view.bounds.height * 0.6)
            // Comments keep their normal scroll behavior. Only pull down from
            // the top video area while the document is at its upper edge.
            return velocity.y > abs(velocity.x) * 1.4 && startY >= 0 && startY <= videoHeight &&
                view.scrollView.contentOffset.y <= -view.scrollView.adjustedContentInset.top + 8
        }
        func gestureRecognizer(_ gesture: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }
        @objc private func swiped(_ pan: UIPanGestureRecognizer) {
            guard enabled, pan.state == .ended, let view = webView else { return }
            let delta = pan.translation(in: view)
            if delta.y >= 72 && delta.y > abs(delta.x) * 1.4 { leaveWatch() }
        }
    }

    @MainActor
    private final class PlayerTouchObserver: UIGestureRecognizer {
        var touched: (CGPoint) -> Void = { _ in }
        override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
            if let touch = touches.first, let view { touched(touch.location(in: view)) }
            // Observe without claiming the gesture or delaying website controls.
            state = .failed
        }
    }
}

@MainActor
struct NativeVolumeControl: UIViewRepresentable {
    func makeUIView(context: Context) -> MPVolumeView {
        let view = MPVolumeView(frame: .zero)
        view.showsRouteButton = false
        return view
    }
    func updateUIView(_ view: MPVolumeView, context: Context) {}
}

@MainActor
struct AirPlayControl: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView(frame: .zero)
        view.prioritizesVideoDevices = true
        view.tintColor = .label
        view.activeTintColor = .systemTeal
        return view
    }
    func updateUIView(_ view: AVRoutePickerView, context: Context) {}
}

@MainActor
struct SeekGesturePad: View {
    let seek: (Double) -> Void
    var interval = 10.0
    @State private var movement = 0.0
    var body: some View {
        HStack(spacing: 0) {
            Text("−\(Int(interval)) s").frame(maxWidth: .infinity, minHeight: 44)
                .contentShape(Rectangle()).onTapGesture(count: 2) { seek(-interval) }
            Image(systemName: "hand.draw").accessibilityHidden(true)
            Text("+\(Int(interval)) s").frame(maxWidth: .infinity, minHeight: 44)
                .contentShape(Rectangle()).onTapGesture(count: 2) { seek(interval) }
        }
        .font(.caption).foregroundStyle(.secondary)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .gesture(DragGesture(minimumDistance: 20)
            .onChanged { movement = $0.translation.width / 5 }
            .onEnded { _ in seek(movement); movement = 0 })
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Spulen: links oder rechts doppelt tippen; horizontal wischen")
        .accessibilityAdjustableAction { seek($0 == .increment ? interval : -interval) }
        .overlay(alignment: .top) {
            if movement != 0 { Text("\(Int(movement)) s").font(.caption).offset(y: -18) }
        }
    }
}
