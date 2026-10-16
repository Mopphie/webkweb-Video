import Foundation

/// Persistence/extension boundary: reject credentials and common signed tokens.
/// Arbitrary URL parameters can still carry secrets; users choose what to save.
enum StoredAddress {
    static func clean(_ value: String) -> String? {
        guard value.utf8.count <= 8192, !value.contains(where: { $0.isWhitespace }),
              var parts = URLComponents(string: value), ["http", "https"].contains(parts.scheme?.lowercased() ?? ""),
              let host = parts.host, !host.isEmpty, parts.user == nil, parts.password == nil else { return nil }
        let sensitive = ["token", "access_token", "auth", "authorization", "key", "api_key", "signature", "sig", "policy", "expires", "credential", "session", "sessionid", "jwt", "password", "passwd", "pwd", "client_secret", "refresh_token", "id_token", "code", "state", "samlresponse", "ticket", "otp"]
        guard !(parts.queryItems ?? []).contains(where: {
            let name = $0.name.lowercased()
            return sensitive.contains(name) || name.hasPrefix("x-amz-") || name.hasPrefix("x-goog-")
        }) else { return nil }
        if let fragment = parts.fragment {
            let names = sensitive.joined(separator: "|")
            if fragment.range(of: "(^|[?&#;])(" + names + "|x-amz-[^=]*|x-goog-[^=]*)=", options: [.regularExpression, .caseInsensitive]) != nil { return nil }
        }
        parts.scheme = parts.scheme?.lowercased(); parts.host = host.lowercased()
        return parts.url?.absoluteString
    }
}
