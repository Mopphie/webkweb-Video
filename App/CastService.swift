import SwiftUI

#if canImport(GoogleCast)
import GoogleCast
#endif

@MainActor
final class CastService: ObservableObject {
    static let shared = CastService()
    @Published private(set) var status = ""

    static var isAvailable: Bool {
        #if canImport(GoogleCast)
        return true
        #else
        return false
        #endif
    }

    private init() {}

    func configure() {
        #if canImport(GoogleCast)
        let criteria = GCKDiscoveryCriteria(applicationID: kGCKDefaultMediaReceiverApplicationID)
        GCKCastContext.setSharedInstanceWith(GCKCastOptions(discoveryCriteria: criteria))
        GCKCastContext.sharedInstance().useDefaultExpandedMediaControls = true
        #endif
    }

    func load(_ media: DirectMedia, title: String, at time: Double) -> Bool {
        #if canImport(GoogleCast)
        guard let session = GCKCastContext.sharedInstance().sessionManager.currentCastSession,
              let client = session.remoteMediaClient else {
            status = "Wähle zuerst ein Cast-Gerät."
            return false
        }
        let metadata = GCKMediaMetadata(metadataType: .generic)
        metadata.setString(title, forKey: kGCKMetadataKeyTitle)
        let builder = GCKMediaInformationBuilder(contentURL: media.url)
        builder.contentType = media.contentType
        builder.streamType = .buffered
        builder.metadata = metadata
        let load = GCKMediaLoadRequestDataBuilder()
        load.mediaInformation = builder.build()
        load.autoplay = true
        load.startTime = max(0, time)
        client.loadMedia(with: load.build())
        status = "Cast-Anfrage gesendet. Der Empfänger muss den Medienlink selbst erreichen können."
        return true
        #else
        status = "Dieser Build enthält kein Google Cast SDK. AirPlay ist verfügbar."
        return false
        #endif
    }

    func pause() {
        #if canImport(GoogleCast)
        GCKCastContext.sharedInstance().sessionManager.currentCastSession?.remoteMediaClient?.pause()
        #endif
    }
}

#if canImport(GoogleCast)
struct CastDeviceButton: UIViewRepresentable {
    func makeUIView(context: Context) -> GCKUICastButton {
        let button = GCKUICastButton(frame: .zero)
        button.tintColor = .label
        return button
    }
    func updateUIView(_ view: GCKUICastButton, context: Context) {}
}
#endif
