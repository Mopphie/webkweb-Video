import SwiftUI
import WebKit
import MediaPlayer
import AVKit

@MainActor
struct BrowserWebView: UIViewRepresentable {
    let tab: BrowserTab
    func makeUIView(context: Context) -> WKWebView { tab.webView }
    func updateUIView(_ view: WKWebView, context: Context) {}
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
    @State private var movement = 0.0
    var body: some View {
        HStack(spacing: 0) {
            Text("−10 s").frame(maxWidth: .infinity, minHeight: 44)
                .contentShape(Rectangle()).onTapGesture(count: 2) { seek(-10) }
            Image(systemName: "hand.draw").accessibilityHidden(true)
            Text("+10 s").frame(maxWidth: .infinity, minHeight: 44)
                .contentShape(Rectangle()).onTapGesture(count: 2) { seek(10) }
        }
        .font(.caption).foregroundStyle(.secondary)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .gesture(DragGesture(minimumDistance: 20)
            .onChanged { movement = $0.translation.width / 5 }
            .onEnded { seek(movement); movement = 0 })
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Spulen: links oder rechts doppelt tippen; horizontal wischen")
        .accessibilityAdjustableAction { seek($0 == .increment ? 10 : -10) }
        .overlay(alignment: .top) {
            if movement != 0 { Text("\(Int(movement)) s").font(.caption).offset(y: -18) }
        }
    }
}
