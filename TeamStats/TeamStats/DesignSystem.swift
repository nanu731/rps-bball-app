import SwiftUI
import UIKit

enum TeamStatsStyle {
    // Keep supporting copy legible while retaining the platform's adaptive label color.
    static let secondaryText = Color.primary.opacity(0.75)
    // System red is too light for normal-size warning text on a white surface.
    static let errorText = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 1, green: 105 / 255, blue: 97 / 255, alpha: 1)
            : UIColor(red: 180 / 255, green: 35 / 255, blue: 24 / 255, alpha: 1)
    })
    // Provisional maroon, not an official school color specification.
    // Filled controls use a darker dark-mode variant so their white labels stay readable.
    static let filledAccent = Color(uiColor: UIColor { traits in
        if traits.userInterfaceStyle == .dark {
            UIColor(red: 180 / 255, green: 73 / 255, blue: 107 / 255, alpha: 1)
        } else {
            UIColor(red: 122 / 255, green: 31 / 255, blue: 61 / 255, alpha: 1)
        }
    })
}

/// Real game facts, with provenance stated independently of the brand color.
struct GameIdentity: View {
    let opponent: String
    let date: String
    let venue: String
    let kind: String
    let location: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(opponent).font(.title2.bold())
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Text("\(date) · \(venue) · \(kind)")
                .font(.subheadline).fixedSize(horizontal: false, vertical: true)
            Label(location, systemImage: location == "On this device" ? "iphone" : "person.2")
                .font(.subheadline.weight(.semibold)).foregroundStyle(Color.accentColor)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
    }
}

struct TeamTaskLabel: View {
    let title: String
    let detail: String
    let symbol: String

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: symbol).font(.title3).foregroundStyle(Color.accentColor)
                .frame(width: 24).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline).foregroundStyle(.primary)
                Text(detail).font(.subheadline).foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(minHeight: 44, alignment: .leading).padding(.vertical, 8)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title).accessibilityHint(detail)
    }
}

/// Score context is an entered-data subtotal, never a manufactured final result.
struct GameLedgerHeader: View {
    let game: Game
    let points: String
    let coverage: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("TeamStats").font(.headline)
                Spacer()
                Text("After game").font(.subheadline)
            }
            .padding(16).foregroundStyle(.white).background(TeamStatsStyle.filledAccent)
            VStack(alignment: .leading, spacing: 12) {
                Text("\(game.date.formatted(.dateTime.month().day().year())) · \(game.kind.rawValue)")
                    .font(.subheadline).foregroundStyle(Color.white.opacity(0.8))
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 24) { ourScore; opponentScore }
                    VStack(alignment: .leading, spacing: 16) { ourScore; opponentScore }
                }
            }
            .padding(16).foregroundStyle(.white)
            .background(Color(white: 0.06))
            Label("Local draft — incomplete and unreviewed", systemImage: "pencil")
                .font(.subheadline.weight(.semibold)).padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(uiColor: .secondarySystemBackground))
        }
    }

    private var ourScore: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Our team · \(game.venue.rawValue)").font(.headline)
            Text(points).font(.largeTitle.bold()).monospacedDigit()
            Text(coverage).font(.footnote)
            Text("Not a final score").font(.footnote)
        }.frame(minWidth: 140, maxWidth: .infinity, alignment: .leading)
    }

    private var opponentScore: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(game.opponent).font(.headline)
            Text("Not available").font(.title3.weight(.semibold))
            Text("Opponent score is not collected in player box scores.").font(.footnote)
        }.frame(minWidth: 140, maxWidth: .infinity, alignment: .leading)
    }
}
