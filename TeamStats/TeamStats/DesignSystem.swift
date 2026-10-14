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
