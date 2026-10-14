import SwiftUI
import UniformTypeIdentifiers

@MainActor
struct FilterSourcesView: View {
    @EnvironmentObject private var browser: BrowserModel
    @ObservedObject private var rules = RuleStore.shared
    @State private var title = ""
    @State private var address = ""
    @State private var importFile = false
    @State private var error: String?
    var body: some View {
        Form {
            Section("Quellen") {
                ForEach($browser.options.sources) { $source in
                    VStack(alignment: .leading, spacing: 4) {
                        Toggle(source.title, isOn: $source.enabled)
                        Text(rules.sourceStatus[source.id] ?? (source.localFile == nil ? source.address : "Lokale importierte Liste"))
                            .font(.caption).foregroundStyle(.secondary).lineLimit(3)
                    }.swipeActions { Button("Entfernen", role: .destructive) { let id = source.id; browser.options.sources.removeAll { $0.id == id } } }
                }
            }
            Section("HTTPS-Quelle hinzufügen") {
                TextField("Name", text: $title)
                TextField("Listen-URL", text: $address).textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                Button("Hinzufügen") {
                    guard let url = ReleaseConfiguration.publicURL(address) else { error = "HTTPS-URL ohne Zugangsdaten erforderlich."; return }
                    browser.options.sources.append(FilterSource(title: title.isEmpty ? (url.host ?? "Liste") : title, address: url.absoluteString))
                    title = ""; address = ""; error = nil
                }
                Button("Textliste importieren", systemImage: "square.and.arrow.down") { importFile = true }
            }
            Section {
                Text("Domain-/Hosts-Listen und unterstützte AdGuard/EasyList-Netzwerkregeln. Keine Scriptlets oder kosmetischen Filter. Nicht sicher abbildbare Ausnahmen führen zu einer klaren Quellenfehlermeldung; valide andere Quellen und Basisfilter bleiben aktiv. Alle unterstützten Regeln werden auf mehrere WebKit-Listen verteilt.").font(.caption).foregroundStyle(.secondary)
                if let error { Text(error).foregroundStyle(.red) }
                Button("Quellen jetzt laden") { Task { await rules.refreshIfNeeded(force: true) } }.disabled(rules.refreshing)
            }
        }.navigationTitle("Filterquellen")
            .fileImporter(isPresented: $importFile, allowedContentTypes: [.plainText]) { result in
                do {
                    let url = try result.get(), access = url.startAccessingSecurityScopedResource()
                    defer { if access { url.stopAccessingSecurityScopedResource() } }
                    let text = try String(contentsOf: url, encoding: .utf8)
                    browser.options.sources.append(try rules.importRules(text, title: url.deletingPathExtension().lastPathComponent))
                    error = nil
                } catch { self.error = error.localizedDescription }
            }
    }
}

@MainActor
struct FilterAllowlistView: View {
    var sponsor = false
    private var hosts: [String] { sponsor ? browser.options.sponsorAllowlist : browser.options.allowlist }
    @EnvironmentObject private var browser: BrowserModel
    @State private var address = ""
    @State private var error: String?
    var body: some View {
        Form {
            Section("Filter auf diesen Seiten aus") {
                ForEach(hosts, id: \.self) { host in
                    Text(host).swipeActions { Button("Entfernen", role: .destructive) { if sponsor { browser.options.sponsorAllowlist.removeAll { $0 == host } } else { browser.options.allowlist.removeAll { $0 == host } } } }
                }
            }
            Section {
                TextField("Domain oder Webseitenadresse", text: $address).textInputAutocapitalization(.never).autocorrectionDisabled()
                Button("Erlauben") {
                    guard let url = AddressResolver.directURL(address), let host = url.host?.lowercased() else { error = "Gültige Domain erforderlich."; return }
                    if sponsor { if !browser.options.sponsorAllowlist.contains(host) { browser.options.sponsorAllowlist.append(host) } }
                    else if !browser.options.allowlist.contains(host) { browser.options.allowlist.append(host) }
                    address = ""; error = nil
                }
                if let error { Text(error).foregroundStyle(.red) }
                Text("Gilt für diese Domain und ihre Unterdomains. Die Liste wird nur für normale lokale Einstellungen gespeichert, ohne an Filteranbieter zu senden.").font(.caption).foregroundStyle(.secondary)
            }
        }.navigationTitle(sponsor ? "SponsorBlock-Ausnahmen" : "Erlaubte Webseiten")
    }
}
