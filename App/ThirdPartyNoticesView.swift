import SwiftUI

struct ThirdPartyNoticesView: View {
    private var notice: String {
        guard let url = Bundle.main.url(forResource: "ThirdPartyNotices", withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return "Lizenzhinweise konnten nicht geladen werden." }
        return text
    }
    private var license: String {
        guard let url = Bundle.main.url(forResource: "GPL-3.0", withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return "Lizenztext konnte nicht geladen werden." }
        return text
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text(notice)
                Text(license).font(.caption)
            }.frame(maxWidth: .infinity, alignment: .leading).padding().textSelection(.enabled)
        }.navigationTitle("Lizenzen")
    }
}
