import Foundation

/// The state of the snowpack — the single value that decides how the game *plays*.
///
/// This is the concept's load-bearing idea. Rendering falling snow when it snows in the
/// player's city is a filter: noticed once, screenshotted, then ignored. A snowpack state
/// changes which decision is correct — when to carve, when to straight-line, whether a
/// landing will be caught or will wash out — so the same terrain seed plays like a
/// different game across states, and yesterday's line is wrong today.
public enum SnowState: String, Sendable, CaseIterable, Codable {

    /// Deep, cold, recent. Forgiving and slow; the reward state.
    case powder

    /// Settled and consistent. The neutral baseline everything else is judged against.
    case packed

    /// Refrozen after a thaw. Fast, loud, and utterly unforgiving of a late edge.
    case crust

    /// Warm and wet. Grabby — punishes over-carving and bleeds speed the harder you push.
    case slush

    /// Hard-frozen and scoured. Maximum speed, minimum grip.
    case ice

    /// Fresh snow redistributed by wind into uneven loaded pockets. Unpredictable.
    case windSlab

    public var displayName: String {
        switch self {
        case .powder: "Powder"
        case .packed: "Packed"
        case .crust: "Breakable Crust"
        case .slush: "Spring Slush"
        case .ice: "Boilerplate"
        case .windSlab: "Wind Slab"
        }
    }

    /// Short line shown under the conditions header. Ski-report register, not marketing.
    public var reportLine: String {
        switch self {
        case .powder: "Deep and light. Let them run."
        case .packed: "Firm, even, predictable."
        case .crust: "Refrozen overnight. Pick your line early."
        case .slush: "Heavy and warm. Don't fight it."
        case .ice: "Scoured hard. Edges only."
        case .windSlab: "Loaded and uneven. Expect surprises."
        }
    }
}

extension SnowState {

    /// Classifies the snowpack from mountain weather.
    ///
    /// Ordering is deliberate and is itself the model: the tests below it are arranged
    /// most-destructive-first, because a snowpack that has been rained on and refrozen is
    /// crust *no matter how much powder fell on top of it*. Evaluating "was there fresh
    /// snow?" first would produce a game that says powder on a day every skier would
    /// recognise as survival crust.
    public static func classify(_ weather: MountainWeather) -> SnowState {

        let hasThawed = weather.maxTemperature24hC > 0.5
        let isFrozenNow = weather.temperatureC < -0.5
        let isDeepFrozen = weather.temperatureC < -6
        let freshSnow = weather.freshSnowCm
        let gusts = weather.windGustKmh

        // 1. Freeze–thaw, or rain that has since frozen. The defining bad-day snowpack,
        //    and the reason 24 h history has to be in the model at all.
        if hasThawed && isFrozenNow {
            return freshSnow > 15 ? .windSlab : .crust
        }

        // 2. Actively warm. Nothing can be powder above freezing.
        if weather.temperatureC > 1.5 || weather.isRainingAtAltitude {
            return .slush
        }

        // 3. Meaningful new snow, cold enough to stay dry.
        if freshSnow >= 8 && weather.temperatureC <= -2 {
            // Wind is what turns a powder day into a slab day. Same snow, redistributed
            // into loaded pockets and scoured ribs.
            return gusts >= 45 ? .windSlab : .powder
        }

        // 4. Cold, snowless and wind-scoured: boilerplate. Wind is what strips the soft
        //    layer off and polishes what remains, so it is required here rather than
        //    optional — plain cold does not make ice.
        if isDeepFrozen && freshSnow < 2 && gusts >= 35 {
            return .ice
        }

        // 5. Extreme cold with a long dry spell. The threshold is well below the everyday
        //    winter range on purpose: an earlier −6 °C cut-off classified an ordinary calm
        //    winter day as ice, which the running build showed sitting directly on top of
        //    real observations (Reykjavík at −5 °C). Ice has to stay rare to mean anything.
        if weather.temperatureC < -12 && freshSnow < 1 {
            return .ice
        }

        // 6. Everything else settles out as ordinary packed snow.
        return .packed
    }
}
