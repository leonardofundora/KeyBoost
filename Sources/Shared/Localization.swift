import Foundation

/// Atajo para texto traducible. Las claves son el texto en inglés, que es el idioma base.
///
/// En SwiftUI, `Text("literal")` ya se traduce solo porque el literal se convierte en
/// `LocalizedStringKey`. Esta función es para lo demás: menús de AppKit y cadenas que
/// hay que componer antes de mostrarlas.
func L(_ key: String) -> String {
    NSLocalizedString(key, comment: "")
}

/// Igual, pero con formato. Los marcadores van en el propio `.strings`.
func L(_ key: String, _ arguments: CVarArg...) -> String {
    String(format: NSLocalizedString(key, comment: ""), arguments: arguments)
}
