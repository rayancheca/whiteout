import Foundation

/// The result of a completed run.
public struct RunScore: Sendable, Equatable {

    public let distanceM: Double
    public let airTimeS: Double
    public let flips: Int
    public let snowState: SnowState
    public let peak: Peak
    public let endedInCrash: Bool

    public init(
        distanceM: Double,
        airTimeS: Double,
        flips: Int,
        snowState: SnowState,
        peak: Peak,
        endedInCrash: Bool
    ) {
        self.distanceM = distanceM
        self.airTimeS = airTimeS
        self.flips = flips
        self.snowState = snowState
        self.peak = peak
        self.endedInCrash = endedInCrash
    }

    public static func from(_ state: SkierState, conditions: RunConditions, peak: Peak) -> RunScore {
        RunScore(
            distanceM: state.distanceM,
            airTimeS: state.totalAirTimeS,
            flips: state.flips,
            snowState: conditions.snowState,
            peak: peak,
            endedInCrash: state.hasCrashed
        )
    }

    /// Final score.
    ///
    /// Distance dominates deliberately. Air and flips are bonuses that reward taking risk,
    /// but a player who simply survives a long way down still posts a respectable number —
    /// otherwise a bad-conditions day would be unplayable rather than merely different.
    public var points: Int {
        Int(distanceM.rounded())
            + Int((airTimeS * 55).rounded())
            + flips * 240
    }

    /// One-line summary for the share card.
    ///
    /// The conditions are part of the boast. "4,120 m on breakable crust" is a claim about
    /// the day, not just about the player, and it is the reason the card is worth posting.
    public var shareLine: String {
        "\(Int(distanceM))m · \(snowState.displayName) · \(peak.name)"
    }
}
