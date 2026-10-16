import SwiftUI
import WebKit
import MediaPlayer
import AVKit

@MainActor
struct BrowserWebView: UIViewRepresentable {
    let tab: BrowserTab
    var watchPresentation = false
    var restoreBrowser: () -> Void = {}
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
        coordinator.restoreBrowser = restoreBrowser
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
        var restoreBrowser: () -> Void = {}
        var playerTouch: (CGPoint) -> Void = { _ in }
        private final class Pull {
            let url: URL?
            let restore: () -> Void
            var beganOnVideo = false
            var ended = false
            init(url: URL?, restore: @escaping () -> Void) { self.url = url; self.restore = restore }
        }
        private var pull: Pull?
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
        func detach() { webView?.removeGestureRecognizer(pan); webView?.removeGestureRecognizer(touchObserver); webView = nil; playerTouch = { _ in }; restoreBrowser = {}; enabled = false; pull = nil }
        func gestureRecognizerShouldBegin(_ gesture: UIGestureRecognizer) -> Bool {
            guard enabled, let view = webView, let pan = gesture as? UIPanGestureRecognizer else { return false }
            let velocity = pan.velocity(in: view)
            return velocity.y > abs(velocity.x) * 1.4
        }
        func gestureRecognizer(_ gesture: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }
        @objc private func swiped(_ pan: UIPanGestureRecognizer) {
            guard enabled, let view = webView else { pull = nil; return }
            let delta = pan.translation(in: view)
            switch pan.state {
            case .began:
                let point = pan.location(in: view)
                let start = CGPoint(x: point.x - delta.x, y: point.y - delta.y)
                let candidate = Pull(url: view.url, restore: restoreBrowser)
                pull = candidate
                // Read the real visible video rectangle, not an assumed 16:9
                // box at y=0. YouTube headers and document scroll offsets vary.
                // No DOM changes, playback calls, stream URLs or iframe access.
                guard view.bounds.width > 0, view.bounds.height > 0 else { pull = nil; return }
                view.callAsyncJavaScript("""
                    const viewport = window.visualViewport;
                    const x = fractionX * (viewport?.width || innerWidth) + (viewport?.offsetLeft || 0);
                    const y = fractionY * (viewport?.height || innerHeight) + (viewport?.offsetTop || 0);
                    return Array.from(document.querySelectorAll('video')).some(video => {
                        const r = video.getBoundingClientRect(), style = getComputedStyle(video);
                        return r.width > 0 && r.height > 0 && Number(style.opacity) > 0 && style.visibility === 'visible' &&
                            style.display !== 'none' && x >= r.left && x <= r.right &&
                            y >= r.top - 12 && y <= r.bottom;
                    });
                    """, arguments: ["fractionX": Double(start.x / view.bounds.width), "fractionY": Double(start.y / view.bounds.height)],
                    in: nil, in: BrowserTab.world) { [weak self] result in
                        Task { @MainActor in
                            guard let self, self.pull === candidate else { return }
                            if case .success(let value) = result { candidate.beganOnVideo = value as? Bool == true }
                            self.finishPull(candidate)
                        }
                    }
            case .ended:
                guard let pull else { return }
                pull.ended = delta.y >= 72 && delta.y > abs(delta.x) * 1.4
                if pull.ended {
                    finishPull(pull)
                    // A delayed WebContent reply must not change the UI long
                    // after the user has finished this gesture.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
                        if self?.pull === pull { self?.pull = nil }
                    }
                } else { self.pull = nil }
            case .cancelled, .failed: pull = nil
            default: break
            }
        }
        private func finishPull(_ candidate: Pull) {
            guard pull === candidate, candidate.ended, candidate.beganOnVideo,
                  enabled, webView?.url == candidate.url else { return }
            pull = nil
            candidate.restore()
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
