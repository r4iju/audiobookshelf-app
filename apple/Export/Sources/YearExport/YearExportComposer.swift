import SwiftUI
import UIKit

/// Share composer for one immutable snapshot. A new snapshot (another year or account)
/// replaces the whole composer state rather than updating it in place.
public struct YearExportComposer: View {
    private let snapshot: YearExportSnapshot
    public init(snapshot: YearExportSnapshot) { self.snapshot = snapshot }
    public var body: some View { ComposerContent(snapshot: snapshot).id(snapshot.id) }
}

/// The composer wrapped for modal presentation.
public struct YearExportSheet: View {
    private let snapshot: YearExportSnapshot
    private let onDone: () -> Void
    public init(snapshot: YearExportSnapshot, onDone: @escaping () -> Void) {
        self.snapshot = snapshot
        self.onDone = onDone
    }
    public var body: some View {
        NavigationView {
            YearExportComposer(snapshot: snapshot)
                .navigationTitle("Share \(String(snapshot.year))")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done", action: onDone) } }
        }.navigationViewStyle(StackNavigationViewStyle())
    }
}

@MainActor final class YearExportComposerModel: ObservableObject {
    let snapshot: YearExportSnapshot
    @Published private(set) var layout: YearExportLayout
    @Published private(set) var preview: YearExportArtifact?

    init(snapshot: YearExportSnapshot) {
        self.snapshot = snapshot
        layout = snapshot.availableLayouts[0]
    }

    var designs: [YearExportDesign] {
        YearExportDesign.allCases.filter { design in snapshot.availableLayouts.contains { $0.design == design } }
    }

    func select(design: YearExportDesign) {
        guard design != layout.design, designs.contains(design) else { return }
        layout = YearExportLayout(design: design, shape: layout.shape) ?? YearExportLayout(design: design, shape: design.shapes[0])!
    }

    func select(shape: YearExportShape) {
        if let next = YearExportLayout(design: layout.design, shape: shape) { layout = next }
    }

    func refreshPreview() async {
        let snapshot = snapshot, layout = layout
        let artifact = await Task.detached(priority: .userInitiated) { YearExportRenderer.render(snapshot, layout: layout) }.value
        guard layout == self.layout else { return }
        preview = artifact
    }

    func artifactForSharing() -> YearExportArtifact {
        if let preview, preview.layout == layout { return preview }
        return YearExportRenderer.render(snapshot, layout: layout)
    }
}

private struct ComposerContent: View {
    @StateObject private var model: YearExportComposerModel
    @State private var request: ShareRequest?
    @Environment(\.horizontalSizeClass) private var sizeClass

    init(snapshot: YearExportSnapshot) { _model = StateObject(wrappedValue: YearExportComposerModel(snapshot: snapshot)) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                preview
                if model.designs.count > 1 {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Style").font(.headline)
                        Picker("Style", selection: Binding(get: { model.layout.design }, set: model.select(design:))) {
                            ForEach(model.designs) { Text($0.title).tag($0) }
                        }.pickerStyle(SegmentedPickerStyle())
                        Text(model.layout.design.summary).font(.footnote).foregroundColor(.secondary)
                    }
                }
                if model.layout.design.shapes.count > 1 {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Format").font(.headline)
                        Picker("Format", selection: Binding(get: { model.layout.shape }, set: model.select(shape:))) {
                            ForEach(model.layout.design.shapes) { Text($0.title).tag($0) }
                        }.pickerStyle(SegmentedPickerStyle())
                    }
                }
                Button(action: share) {
                    Label("Share Image", systemImage: "square.and.arrow.up")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .foregroundColor(.black)
                        .background(Color(red: 1, green: 0.86, blue: 0.44))
                        .cornerRadius(14)
                }
                .background(ActivityPresenter(request: $request))
                .accessibilityHint("Opens the share sheet with this image and a text summary.")
                Text("The image is created on this device from your \(String(model.snapshot.year)) statistics.")
                    .font(.footnote).foregroundColor(.secondary)
            }
            .padding()
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
        }
        .onAppear { Task { await model.refreshPreview() } }
        .onChange(of: model.layout) { _ in Task { await model.refreshPreview() } }
    }

    private var preview: some View {
        let size = model.layout.shape.pixelSize
        return ZStack {
            if let artifact = model.preview, artifact.layout == model.layout, let image = UIImage(data: artifact.pngData) {
                Image(uiImage: image).resizable().interpolation(.high)
                    .accessibilityLabel(Text(artifact.accessibilityLabel))
            } else {
                Color(white: 0.12)
                ProgressView().accessibilityLabel("Creating image")
            }
        }
        .aspectRatio(size.width / size.height, contentMode: .fit)
        .frame(maxWidth: .infinity, maxHeight: sizeClass == .regular ? 620 : 480)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: Color.black.opacity(0.25), radius: 16, y: 8)
        .accessibilityElement(children: .combine)
    }

    private func share() {
        request = ShareRequest(artifact: model.artifactForSharing())
    }
}

/// One exported PNG in its own temporary folder. The folder is removed when the share sheet
/// reports completion, or when the last holder (the pending request or the share sheet) releases
/// it, so a share consumer never loses the file while it can still read it.
final class YearExportShareFile {
    let url: URL
    private let directory: URL

    init(artifact: YearExportArtifact, root: URL) throws {
        directory = root.appendingPathComponent(UUID().uuidString, isDirectory: true)
        url = directory.appendingPathComponent(artifact.fileName)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try artifact.pngData.write(to: url, options: .completeFileProtection)
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
    }

    func remove() { try? FileManager.default.removeItem(at: directory) }
    deinit { remove() }
}

struct ShareRequest: Identifiable {
    let id = UUID()
    let items: [Any]
    let file: YearExportShareFile?

    init(artifact: YearExportArtifact, root: URL = FileManager.default.temporaryDirectory.appendingPathComponent("YearExport", isDirectory: true)) {
        if let file = try? YearExportShareFile(artifact: artifact, root: root) {
            items = [file.url, artifact.shareText]
            self.file = file
        } else {
            items = [UIImage(data: artifact.pngData) as Any, artifact.shareText]
            file = nil
        }
    }
}

enum YearExportActivity {
    /// The completion handler holds the file, tying its lifetime to the share sheet itself.
    static func controller(for request: ShareRequest, onFinish: @escaping () -> Void) -> UIActivityViewController {
        let activity = UIActivityViewController(activityItems: request.items, applicationActivities: nil)
        let file = request.file
        activity.completionWithItemsHandler = { _, _, _, _ in
            file?.remove()
            onFinish()
        }
        return activity
    }

    /// Returns false, leaving nothing presented, when the composer is no longer on screen or is
    /// already presenting; releasing the request then removes its file.
    static func present(_ request: ShareRequest, from controller: UIViewController, onFinish: @escaping () -> Void) -> Bool {
        guard controller.view.window != nil, controller.presentedViewController == nil else { return false }
        let activity = Self.controller(for: request, onFinish: onFinish)
        activity.popoverPresentationController?.sourceView = controller.view
        activity.popoverPresentationController?.sourceRect = controller.view.bounds
        controller.present(activity, animated: true)
        return activity.presentingViewController != nil
    }
}

/// Presents UIActivityViewController from a view behind the share button, so the iPad popover
/// anchors to the button rather than to a full-screen sheet.
private struct ActivityPresenter: UIViewControllerRepresentable {
    @Binding var request: ShareRequest?

    final class Coordinator { var scheduled: UUID? }
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeUIViewController(context: Context) -> UIViewController { UIViewController() }

    func updateUIViewController(_ controller: UIViewController, context: Context) {
        guard let request, context.coordinator.scheduled != request.id else { return }
        context.coordinator.scheduled = request.id
        let binding = $request
        // Presenting is deferred out of the SwiftUI update; by then the composer may be gone.
        DispatchQueue.main.async { [weak controller] in
            guard let controller, binding.wrappedValue?.id == request.id else { return }
            let presented = YearExportActivity.present(request, from: controller) {
                if binding.wrappedValue?.id == request.id { binding.wrappedValue = nil }
            }
            if !presented { binding.wrappedValue = nil }
        }
    }
}
