import Foundation

extension NativeStrings {
    /// Shows the shared core's text, such as its failure descriptions, in the language chosen at the time it is read.
    static func installCoreText(bundle: Bundle = .main) {
        CoreText.lookup = { english, arguments in
            NativeStrings(language: .current, bundle: bundle)(english, arguments: arguments)
        }
    }
}
