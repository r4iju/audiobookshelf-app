import SwiftUI

struct NoticesView: View {
    @Environment(\.nativeStrings) private var l10n

    var body: some View {
        List {
            Section {
                Text("Audiobook Loft").font(.headline).accessibilityAddTraits(.isHeader)
                    .listRowBackground(Color.clear)
                TVReadableText(
                    text: l10n("Audiobook Loft began in an independently maintained Audiobookshelf fork. This native Apple client is independently implemented and connects to compatible servers. It is not affiliated with or endorsed by the Audiobookshelf project."),
                    identifier: "notices-origin")
            }
            Section {
                Text(l10n("License")).font(.headline).accessibilityAddTraits(.isHeader)
                    .listRowBackground(Color.clear)
                TVReadableText(
                    text: l10n("This native Apple client is available under the MIT license. Bundled reader libraries retain their own licenses. Source and notices: https://github.com/r4iju/audiobookshelf-app/releases"),
                    identifier: "notices-license")
            }
        }
        .frame(maxWidth: 1400)
        .padding(.horizontal, 90)
        .tvNavigationTitle(l10n("Source and license notices"))
    }
}
