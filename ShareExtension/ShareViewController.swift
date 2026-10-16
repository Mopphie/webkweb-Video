import UIKit
import UniformTypeIdentifiers

/// No network or automatic extraction. A user explicitly sends one normal link.
final class ShareViewController: UIViewController {
    private let stack = UIStackView()
    private let address = UITextField()
    private let status = UILabel()
    override func viewDidLoad() {
        super.viewDidLoad(); view.backgroundColor = .systemBackground
        stack.axis = .vertical; stack.spacing = 20; stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 24), stack.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -24), stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 24)])
        let heading = UILabel(); heading.text = "Link an DevnTube"; heading.font = .preferredFont(forTextStyle: .title2); heading.adjustsFontForContentSizeCategory = true; stack.addArrangedSubview(heading)
        address.placeholder = "HTTP(S)-Link"; address.keyboardType = .URL; address.autocapitalizationType = .none; address.autocorrectionType = .no; address.borderStyle = .roundedRect; address.accessibilityLabel = "Geteilter Link"; stack.addArrangedSubview(address)
        let privacy = UILabel(); privacy.text = "Du übernimmst den Link ausdrücklich in den normalen App-Bereich. Keine Cookies oder privaten Sitzungen. Öffne DevnTube innerhalb von 15 Minuten zum Übernehmen."; privacy.numberOfLines = 0; privacy.font = .preferredFont(forTextStyle: .body); privacy.adjustsFontForContentSizeCategory = true; stack.addArrangedSubview(privacy)
        for (title, action) in [("Beim nächsten App-Start öffnen", SharedLinkAction.open), ("Zur Linkqueue", .queue), ("In Mediathek speichern", .save)] {
            let button = UIButton(type: .system); button.setTitle(title, for: .normal); button.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
            button.addAction(UIAction { [weak self] _ in self?.submit(action) }, for: .touchUpInside); stack.addArrangedSubview(button)
        }
        status.numberOfLines = 0; stack.addArrangedSubview(status)
        let cancel = UIButton(type: .system); cancel.setTitle("Abbrechen", for: .normal); cancel.addAction(UIAction { [weak self] _ in self?.extensionContext?.completeRequest(returningItems: nil) }, for: .touchUpInside); stack.addArrangedSubview(cancel)
        if let items = extensionContext?.inputItems as? [NSExtensionItem], let provider = items.flatMap({ $0.attachments ?? [] }).first(where: { $0.hasItemConformingToTypeIdentifier(UTType.url.identifier) || $0.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) }) {
            let type = provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) ? UTType.url.identifier : UTType.plainText.identifier
            provider.loadItem(forTypeIdentifier: type, options: nil) { [weak self] value, _ in
                let text = (value as? URL)?.absoluteString ?? (value as? String) ?? ""
                DispatchQueue.main.async { self?.address.text = StoredAddress.clean(text) ?? "" }
            }
        }
    }
    private func submit(_ action: SharedLinkAction) {
        guard let clean = StoredAddress.clean(address.text ?? "") else { status.text = "Gültiger Link ohne Zugangsdaten oder signierte Tokens erforderlich."; return }
        guard ShareInbox.submit(SharedLink(address: clean, action: action)) else { status.text = "Gemeinsamer Speicher ist nicht verfügbar. Link manuell in DevnTube öffnen."; return }
        extensionContext?.completeRequest(returningItems: nil)
    }
}
