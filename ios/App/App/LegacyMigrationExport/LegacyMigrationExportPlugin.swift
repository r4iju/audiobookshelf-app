//
//  LegacyMigrationExportPlugin.swift
//  App
//
//  Exports this app's library as a credential-free `.absmigration` package that the user saves
//  through the Files app and imports into the new app.
//

import Capacitor
import Foundation
import LegacyRealmExport
import RealmSwift
import UIKit

@objc(LegacyMigrationExport)
public class LegacyMigrationExportPlugin: CAPPlugin, CAPBridgedPlugin, UIDocumentPickerDelegate {
    public var identifier = "LegacyMigrationExportPlugin"
    public var jsName = "LegacyMigrationExport"
    public let pluginMethods: [CAPPluginMethod] = [
        CAPPluginMethod(name: "exportArchive", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "saveArchive", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "discardArchive", returnType: CAPPluginReturnPromise)
    ]

    // Main thread only.
    private var activeSave: (picker: UIDocumentPickerViewController, done: LegacyExportSession.SaveCompletion)?

    // Created with the plugin, before any call, so every queue shares this one session.
    // Temporary storage: not backed up, and the package is only kept until the user saves it.
    private let session: LegacyExportSession = {
        let temporary = FileManager.default.temporaryDirectory
        return LegacyExportSession(job: LegacyExportJob(
            documents: FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0],
            exportsDirectory: temporary.appendingPathComponent("LegacyMigrationExport", isDirectory: true),
            workDirectory: temporary.appendingPathComponent("LegacyMigrationExportWork", isDirectory: true),
            defaults: .standard
        ))
    }()

    @objc func exportArchive(_ call: CAPPluginCall) {
        let webStorage = (call.getObject("webStorage") ?? [:]).compactMapValues { $0 as? String }
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let result = try autoreleasepool {
                    try self.session.export(webStorage: webStorage, copyRealm: { url in
                        // A consistent copy of the live database, taken through Realm; the live file is only read.
                        try Realm().writeCopy(toFile: url)
                    }, progress: { self.notifyListeners("exportProgress", data: Self.payload($0)) })
                }
                AbsLogger.info("LegacyMigrationExport", message: "Export prepared with \(result.files) files")
                call.resolve(["name": result.url.lastPathComponent, "files": result.files, "bytes": result.bytes])
            } catch {
                AbsLogger.error("LegacyMigrationExport", message: "Export failed")
                Self.reject(call, error, code: "EXPORT_FAILED")
            }
        }
    }

    /// Hands the package to the system exporter as a copy, so the user picks a Files location
    /// (such as On My iPhone) and nothing is uploaded on the app's behalf.
    @objc func saveArchive(_ call: CAPPluginCall) {
        DispatchQueue.main.async {
            self.session.save(presentingWith: self.presentPicker) { outcome in
                switch outcome {
                case let .success(saved):
                    call.resolve(["saved": saved])
                case let .failure(error):
                    Self.reject(call, error, code: "SAVE_FAILED")
                }
            }
        }
    }

    @objc func discardArchive(_ call: CAPPluginCall) {
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try self.session.discard()
                call.resolve()
            } catch {
                Self.reject(call, error, code: "DISCARD_FAILED")
            }
        }
    }

    private func presentPicker(_ url: URL, done: @escaping LegacyExportSession.SaveCompletion) {
        guard activeSave == nil, let presenter = bridge?.viewController, presenter.viewIfLoaded?.window != nil,
              presenter.presentedViewController == nil, !presenter.isBeingPresented, !presenter.isBeingDismissed
        else { return done(.failure(.saveUnavailable)) }
        let picker = UIDocumentPickerViewController(forExporting: [url], asCopy: true)
        picker.delegate = self
        activeSave = (picker, done)
        presenter.present(picker, animated: true)
        // UIKit may defer this presentation (the picker loads out of process) and refuses one it
        // cannot perform without calling back, so it is checked once it should have begun. The
        // picker can sit inside a system container: any presentation counts, there was none before.
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self, weak presenter] in
            guard let self, self.activeSave?.picker === picker,
                  presenter?.presentedViewController == nil, picker.viewIfLoaded?.window == nil
            else { return }
            self.finishSave(picker, .failure(.saveUnavailable))
        }
    }

    private func finishSave(_ picker: UIViewController, _ outcome: Result<Bool, LegacyExportSessionError>) {
        guard let active = activeSave, active.picker === picker else { return }
        activeSave = nil
        active.done(outcome)
    }

    public func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        finishSave(controller, .success(!urls.isEmpty))
    }

    public func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        finishSave(controller, .success(false))
    }

    private static func reject(_ call: CAPPluginCall, _ error: Error, code: String) {
        call.reject(LegacyExportJob.message(for: error), error as? LegacyExportSessionError == .busy ? "EXPORT_BUSY" : code)
    }

    private static func payload(_ progress: LegacyExportProgress) -> [String: Any] {
        switch progress {
        case .copyingDatabase:
            return ["phase": "copyingDatabase"]
        case .readingDatabase:
            return ["phase": "readingDatabase"]
        case let .copyingFiles(files):
            return ["phase": "copyingFiles", "completedFiles": files.completedFiles, "totalFiles": files.totalFiles,
                    "completedBytes": files.completedBytes, "totalBytes": files.totalBytes]
        }
    }
}
