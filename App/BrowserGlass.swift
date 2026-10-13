import SwiftUI

/// Uses real Liquid Glass when the SDK supports it; the iOS 17 build keeps
/// the same geometry with system material and a restrained edge highlight.
private struct BrowserGlass: ViewModifier {
    let radius: CGFloat
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    @ViewBuilder
    func body(content: Content) -> some View {
        if reduceTransparency {
            content.background(Color(white: 0.13), in: shape)
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

/// Small local glyphs; rendering the homepage never fetches third-party favicons.
struct HomeSiteGlyph: View {
    let site: HomeSite
    var body: some View {
        switch site {
        case .youtube:
            ZStack {
                RoundedRectangle(cornerRadius: 8).fill(Color(red: 1, green: 0.1, blue: 0.14)).frame(width: 36, height: 26)
                Image(systemName: "play.fill").font(.system(size: 13)).foregroundStyle(.white)
            }
        case .twitch:
            ZStack {
                Image(systemName: "bubble.left.fill").font(.system(size: 33)).foregroundStyle(Color(red: 0.6, green: 0.32, blue: 1))
                Image(systemName: "pause.fill").font(.system(size: 14, weight: .black)).foregroundStyle(.white).offset(y: -2)
            }
        case .tiktok:
            Image(systemName: "music.note").font(.system(size: 31, weight: .bold)).foregroundStyle(.white)
                .shadow(color: Color(red: 0.1, green: 0.86, blue: 0.9), radius: 0, x: -1.5, y: -1)
                .shadow(color: Color(red: 1, green: 0.2, blue: 0.36), radius: 0, x: 1.5, y: 1)
        case .rumble:
            Image(systemName: "play.circle.fill").font(.system(size: 34)).foregroundStyle(Color(red: 0.45, green: 0.78, blue: 0.2))
        }
    }
}
