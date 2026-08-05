import Foundation
import Observation

/// App-wide audio mute.
///
/// Shared rather than owned by the scene because `GameView` builds a fresh `MountainScene`
/// whenever conditions re-resolve, while `SpriteView` keeps presenting the old one until
/// `sceneID` changes. A mute passed in at construction would therefore reach a scene nobody
/// is looking at. Shared state is the only thing both sides can see.
///
/// Feel-layer only, per invariant 3: this changes what is *heard*, never what is simulated.
/// A muted run and an unmuted run produce byte-identical `(seed, input tape)` results, so
/// muting can never affect verification or a leaderboard score.
@Observable
@MainActor
final class AudioSettings {

    static let shared = AudioSettings()

    private static let defaultsKey = "whiteout.audio.muted"

    var isMuted: Bool {
        didSet { UserDefaults.standard.set(isMuted, forKey: Self.defaultsKey) }
    }

    private init() {
        isMuted = UserDefaults.standard.bool(forKey: Self.defaultsKey)
    }
}
