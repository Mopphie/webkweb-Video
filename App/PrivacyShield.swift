import SwiftUI
import UIKit
import LocalAuthentication

/// Separate scene window also covers presented sheets in the app switcher.
@MainActor
final class PrivacyShield: ObservableObject {
    @Published private(set) var locked = false
    @Published private(set) var authenticating = false
    @Published var message = ""
    private var cover: UIWindow?
    private var active = true
    private var initialized = false
    private weak var browser: BrowserModel?
    func update(phase: ScenePhase, browser: BrowserModel) {
        self.browser = browser; active = phase == .active
        if !initialized { initialized = true; locked = browser.options.privateLock }
        browser.privacyLocked = locked
        if phase == .background && browser.options.privateLock { locked = true; browser.privacyLocked = true }
        if phase != .active {
            browser.tabs.filter(\.isPrivate).forEach { $0.pauseForPrivacy() }
            if browser.options.privateLock || browser.current.isPrivate { showCover() } else { hideCover() }
        } else if locked { showCover() }
        else { hideCover() }
    }
    private func showCover() {
        if let cover { cover.isHidden = false; return }
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first(where: { $0.activationState != .unattached }) else { return }
        let window = UIWindow(windowScene: scene); window.windowLevel = .alert + 1
        window.rootViewController = UIHostingController(rootView: ShieldView(shield: self))
        window.isHidden = false; cover = window
    }
    private func hideCover() { cover?.isHidden = true; cover = nil }
    func unlock() {
        guard locked, active, !authenticating else { return }
        let context = LAContext(); var failure: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &failure) else { message = "Gerätecode oder Biometrie ist nicht eingerichtet. Richte eine Gerätesperre ein."; return }
        authenticating = true
        context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "DevnTube entsperren") { [weak self] success, _ in
            Task { @MainActor in
                guard let self else { return }; self.authenticating = false
                if success { self.locked = false; self.browser?.privacyLocked = false; self.message = ""; self.hideCover() }
                else { self.message = "Nicht entsperrt. Erneut versuchen." }
            }
        }
    }
}
@MainActor
private struct ShieldView: View {
    @ObservedObject var shield: PrivacyShield
    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()
            VStack(spacing: 24) {
                Image(systemName: "lock.shield").font(.largeTitle)
                Text("DevnTube").font(.title)
                if shield.locked { Button("Entsperren") { shield.unlock() }.buttonStyle(.borderedProminent).disabled(shield.authenticating) }
                if !shield.message.isEmpty { Text(shield.message).font(.callout) }
            }.padding()
        }.privacySensitive()
    }
}
