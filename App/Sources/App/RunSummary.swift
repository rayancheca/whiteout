import SwiftUI
import WhiteoutCore

/// The payoff for a finished run.
///
/// Deliberately not hit-testing, in whole. The card is something to read, not something to
/// operate: the tap that dismisses it falls straight through to the scene, so "restart is one
/// tap" stays literally true anywhere on screen — including on the card itself — and the mute
/// button underneath keeps working.
struct RunSummaryOverlay: View {
    let telemetry: RunTelemetry
    let conditions: RunConditions
    let peak: Peak

    var body: some View {
        ZStack {
            if let score = telemetry.finishedScore(conditions: conditions, peak: peak) {
                // Pushes the live world back a plane so the card reads as the front one. Scaled
                // by scene brightness because the same veil that separates a card from a night
                // sky would be a dirty smear over a lit whiteout — and vice versa.
                Color.black
                    .opacity(0.18 + 0.22 * conditions.palette.exposure)
                    .ignoresSafeArea()

                RunSummaryCard(
                    score: score,
                    headline: telemetry.endReason?.headline ?? "RUN OVER",
                    accent: conditions.palette.skierRim.color
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                .padding(.trailing, 20)
                .transition(
                    reduceMotion
                        ? .opacity
                        : .opacity.combined(with: .scale(scale: 0.94))
                )
            }
        }
        .animation(motion, value: telemetry.isRunOver)
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var motion: Animation {
        reduceMotion
            ? .easeOut(duration: 0.2)
            : .spring(response: 0.42, dampingFraction: 0.86)
    }
}

/// The card. Sits to the trailing side so it never covers the collapsed skier, who is the
/// other half of the story and sits around a third of the way across.
private struct RunSummaryCard: View {
    let score: RunScore
    let headline: String
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(headline)
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                    .tracking(2.2)
                    .foregroundStyle(.white.opacity(0.62))
                // Holds the slot a personal-best badge will take (T-202).
                Spacer(minLength: 0)
            }

            // The distance is the run. At 64pt it is a little over twice the conditions card's
            // headline, which is the contrast that stops this reading as one more HUD chip.
            // Not monospaced, unlike the live readout: those digits tick, these are settled.
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(Int(score.distanceM).formatted())
                    .font(.system(size: 64, weight: .heavy, design: .rounded))
                    .tracking(-1)
                    .foregroundStyle(accent)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text("m")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(accent.opacity(0.55))
            }
            .padding(.top, 4)

            // The conditions are the boast: "4,120 m on breakable crust" is a claim about the
            // day, not only about the player.
            Text(score.conditionsLine)
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.80))
                .padding(.top, 2)

            Rectangle()
                .fill(accent.opacity(0.22))
                .frame(height: 1)
                .padding(.top, 16)

            HStack(spacing: 26) {
                Tally(value: airTimeText, label: "AIR")
                if score.flips > 0 {
                    Tally(value: "×\(score.flips)", label: score.flips == 1 ? "FLIP" : "FLIPS")
                }
                Spacer(minLength: 0)
            }
            .padding(.top, 12)

            Text("TAP TO DROP IN")
                .font(.system(size: 12, weight: .heavy, design: .rounded))
                .tracking(2.4)
                .foregroundStyle(.white.opacity(0.45))
                .padding(.top, 14)
        }
        .padding(20)
        .frame(width: 300, alignment: .leading)
        .background(
            .ultraThinMaterial.opacity(0.82),
            in: RoundedRectangle(cornerRadius: 24, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(.white.opacity(0.14), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.35), radius: 24, y: 10)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(headline). \(Int(score.distanceM)) metres \(score.conditionsLine). "
            + "\(airTimeText) of air. \(score.flips) flips. Tap anywhere to drop in again."
        )
    }

    private var airTimeText: String {
        String(format: "%.1fs", score.airTimeS)
    }

    private struct Tally: View {
        let value: String
        let label: String

        var body: some View {
            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Text(label)
                    .font(.system(size: 9, weight: .heavy, design: .rounded))
                    .tracking(1.2)
                    .foregroundStyle(.white.opacity(0.50))
            }
        }
    }
}
