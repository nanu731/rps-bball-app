import SwiftUI
import UIKit

enum TeamStatsStyle {
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
