import SwiftUI

/// Uses real Liquid Glass when the SDK supports it; the iOS 17 build keeps
/// the same geometry with system material and a restrained edge highlight.
private struct BrowserGlass: ViewModifier {
    let radius: CGFloat
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    @ViewBuilder
    func body(content: Content) -> some View {
        if reduceTransparency {
            content.background(Color(.secondarySystemBackground), in: shape)
                .overlay { shape.strokeBorder(.white.opacity(0.18), lineWidth: 0.75) }
        } else {
            #if compiler(>=6.2)
            if #available(iOS 26.0, *) {
                content.glassEffect(.regular.interactive(), in: shape)
            } else {
                fallback(content)
            }
            #else
            fallback(content)
            #endif
        }
    }

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: radius, style: .continuous) }

    private func fallback(_ content: Content) -> some View {
        content.background(.ultraThinMaterial, in: shape)
            .overlay {
                shape.strokeBorder(LinearGradient(colors: [.white.opacity(0.24), .white.opacity(0.04), .white.opacity(0.12)],
                    startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 0.75)
            }
            .shadow(color: .black.opacity(0.3), radius: 12, y: 6)
    }
}

extension View {
    func browserGlass(radius: CGFloat = 28) -> some View { modifier(BrowserGlass(radius: radius)) }
}

enum HomeSite: String, CaseIterable, Identifiable {
    case youtube, twitch, tiktok, rumble
    var id: String { rawValue }
    var title: String {
        switch self {
        case .youtube: return "YouTube"
        case .twitch: return "Twitch"
        case .tiktok: return "TikTok"
        case .rumble: return "Rumble"
        }
    }
    var address: String {
        switch self {
        case .youtube: return "https://m.youtube.com"
        case .twitch: return "https://www.twitch.tv"
        case .tiktok: return "https://www.tiktok.com"
        case .rumble: return "https://rumble.com"
        }
    }
}

/// Neutral SF Symbols identify bookmarks without reproducing platform logos.
struct HomeSiteGlyph: View {
    let site: HomeSite
    var body: some View {
        Image(systemName: "globe").font(.system(size: 31, weight: .regular)).foregroundStyle(.primary)
    }
}
