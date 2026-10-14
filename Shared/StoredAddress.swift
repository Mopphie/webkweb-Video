import Foundation

/// Persistence boundary shared by the app, Siri entities and the widget.
enum StoredAddress {
    static func clean(_ value: String) -> String? {
        guard var parts = URLComponents(string: value), ["http", "https"].contains(parts.scheme?.lowercased() ?? ""),
              let host = parts.host, !host.isEmpty else { return nil }
        parts.user = nil; parts.password = nil
        return parts.url?.absoluteString
    }
}
