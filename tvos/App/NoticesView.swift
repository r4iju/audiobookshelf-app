import SwiftUI

struct NoticesView: View {
    @Environment(\.nativeStrings) private var l10n

    var body: some View {
        List {
            Section {
                Text("Audiobook Loft").font(.headline).accessibilityAddTraits(.isHeader)
                    .listRowBackground(Color.clear)
                TVReadableText(
                    text: l10n("Audiobook Loft began as an independently maintained fork of the Audiobookshelf app. Its browser and backend have been rewritten. Upstream copyright and license notices are retained. It is not affiliated with or endorsed by the Audiobookshelf project."),
                    identifier: "notices-origin")
            }
            Section {
                Text(l10n("License")).font(.headline).accessibilityAddTraits(.isHeader)
                    .listRowBackground(Color.clear)
                TVReadableText(
                    text: l10n("Open source under GPLv3, with applicable third-party licenses retained. Source and notices: https://github.com/r4iju/audiobookshelf-app/releases"),
                    identifier: "notices-license")
            }
        }
        .frame(maxWidth: 1400)
        .padding(.horizontal, 90)
        .tvNavigationTitle(l10n("Source and license notices"))
    }
}
