import Foundation

struct PlaybackCandidate {
    let id: UUID
    let hasMedia: Bool
    let playing: Bool
}
enum MediaPolicy {
    static func playbackOwner(currentID: UUID, queueID: UUID?, candidates: [PlaybackCandidate]) -> UUID {
        if candidates.contains(where: { $0.id == currentID && $0.hasMedia }) { return currentID }
        if let playing = candidates.first(where: { $0.hasMedia && $0.playing }) { return playing.id }
        if let queueID, candidates.contains(where: { $0.id == queueID && $0.hasMedia }) { return queueID }
        return currentID
    }
    static func requiresAudioSession(localPlaying: Bool, explicitPlay: Bool = false, casting: Bool, stopped: Bool, alreadyActive: Bool = false) -> Bool {
        if alreadyActive && localPlaying { return true } // Await the actual asynchronous pause acknowledgement.
        return !casting && !stopped && (localPlaying || explicitPlay)
    }
    static func nowPlayingRate(playing: Bool, rate: Double) -> Double {
        playing ? (rate.isFinite && rate > 0 ? rate : 1) : 0
    }
}
