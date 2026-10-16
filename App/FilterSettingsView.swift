import SwiftUI

@MainActor
struct FilterSourcesView: View {
    @EnvironmentObject private var browser: BrowserModel
    @State private var address = ""
    @State private var error: String?
    var body: some View {
        Form {
            Section("Website-Sperrliste") {
                ForEach(browser.options.blockedSites, id: \.self) { host in
                    Text(host).swipeActions { Button("Entfernen", role: .destructive) { browser.options.blockedSites.removeAll { $0 == host } } }
                }
                TextField("Domain", text: $address).textInputAutocapitalization(.never).autocorrectionDisabled()
                Button("Website sperren") {
                    guard let host = AddressResolver.directURL(address)?.host?.lowercased(), SiteNavigationPolicy.validBlockedHost(host) else {
                        error = "Gültige Domain erforderlich. Videodienste und ihre Ressourcendomains sind ausgeschlossen."; return
                    }
                    if !browser.options.blockedSites.contains(host) { browser.options.blockedSites.append(host) }
                    address = ""; error = nil
                }
                if let error { Text(error).foregroundStyle(.red) }
            }
            Section {
                Text("Nur bewusst aufgerufene Hauptseiten werden vor dem Laden gesperrt. Kein Werbe-, Unterressourcen-, VPN-, DNS- oder systemweiter Filter. Eingebettete Videos werden nicht gefiltert. Private Tabs übernehmen diese normale lokale Liste nicht.")
                Text("Die frühere Listenfilterung wurde wegen ungeklärter Eingangslizenzen und fehlender wirksamer Abgrenzung bei Diensten und eingebetteten Playern entfernt. Keine automatischen Listenabrufe.")
            }.font(.footnote).foregroundStyle(.secondary)
        }.navigationTitle("Website-Sperrliste")
    }
}
