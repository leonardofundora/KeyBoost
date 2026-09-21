import Foundation

/// Shorthand for translatable text. Keys are the English text, which is the base language.
///
/// In SwiftUI, `Text("literal")` localises itself because the literal becomes a
/// `LocalizedStringKey`. This helper covers everything else: AppKit menus and strings
/// that have to be assembled before they are shown.
func L(_ key: String) -> String {
    NSLocalizedString(key, comment: "")
}

/// Same, with formatting. The placeholders live in the `.strings` file itself.
func L(_ key: String, _ arguments: CVarArg...) -> String {
    String(format: NSLocalizedString(key, comment: ""), arguments: arguments)
}
