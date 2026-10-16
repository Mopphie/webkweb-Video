// swift-tools-version: 6.0
import PackageDescription

// Local, dependency-free Foundation logic tests. This is NOT an iOS build.
let package = Package(
    name: "DevnTubeCore",
    platforms: [.iOS(.v17)],
    products: [.library(name: "DevnTubeCore", targets: ["DevnTubeCore"])],
    targets: [
        .target(name: "DevnTubeCore", path: ".", exclude: ["build", "Docs", "Scripts", "Tests", "UITests", "Widgets", "README.md", "PRIVACY.md", "project.yml", "App/FilterSettingsView.swift", "App/LibraryStore.swift", "App/ThirdPartyNoticesView.swift", "App/WebKWeb.entitlements", "App/BrowserGlass.swift", "App/Models.swift", "App/AudioController.swift", "App/Info.plist", "App/PlayerViews.swift", "App/PrivacyShield.swift", "App/Rules.swift", "App/NativePlayer.swift", "App/Assets.xcassets", "App/Resources", "App/AppIntents.swift", "App/BrowserSession.swift", "App/WebKWebApp.swift", "App/NativePlayerPanel.swift", "App/BrowserView.swift", "App/WebView.swift", "App/LibraryHubView.swift", "App/BrowserSheets.swift", "Shared/FavoriteEntity.swift"], sources: [
            "App/BrowserModels.swift", "App/BrowserPreferences.swift", "App/MediaPolicy.swift",
            "App/PlaybackQueue.swift", "App/SourceCapabilities.swift", "App/LibraryModels.swift",
            "App/NavigationPolicy.swift", "Shared/StoredAddress.swift", "Shared/FavoriteSnapshot.swift"
        ]),
        .testTarget(name: "DevnTubeCoreTests", dependencies: ["DevnTubeCore"], path: "Tests", exclude: ["BrowserIntegrationTests.swift", "MediaPlaybackIntegrationTests.swift", "NativePlayerTests.swift", "WorkspacePrivacyTests.swift", "ComplianceMigrationTests.swift", "Fixtures", "playback.test.cjs", "compliance.test.cjs"], sources: [
            "CoreTests.swift", "QueueTests.swift", "MediaPolicyTests.swift", "LibraryAndPolicyTests.swift"
        ])
    ],
    swiftLanguageModes: [.v5]
)
