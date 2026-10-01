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

    private let queue = DispatchQueue(label: "legacy-migration-export", qos: .userInitiated)
    private var running = false
    private var result: LegacyExportResult?
    private var pendingSave: CAPPluginCall?

    // Temporary storage: not backed up, and the package is only kept until the user saves it.
    private lazy var job: LegacyExportJob = {
        let temporary = FileManager.default.temporaryDirectory
        return LegacyExportJob(
            documents: FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0],
            exportsDirectory: temporary.appendingPathComponent("LegacyMigrationExport", isDirectory: true),
            workDirectory: temporary.appendingPathComponent("LegacyMigrationExportWork", isDirectory: true),
            defaults: .standard
        )
    }()

    @objc func exportArchive(_ call: CAPPluginCall) {
        let webStorage = (call.getObject("webStorage") ?? [:]).compactMapValues { $0 as? String }
        queue.async {
            guard !self.running else {
                call.reject("An export is already in progress.", "EXPORT_RUNNING")
                return
            }
            self.running = true
            self.result = nil
            DispatchQueue.global(qos: .userInitiated).async {
                let outcome = Result {
                    try autoreleasepool {
                        try self.job.run(webStorage: webStorage, copyRealm: { url in
                            // A consistent copy of the live database, taken through Realm; the live file is only read.
                            try Realm().writeCopy(toFile: url)
                        }, progress: { self.notifyListeners("exportProgress", data: Self.payload($0)) })
                    }
                }
                self.queue.async {
                    self.running = false
                    switch outcome {
                    case let .success(result):
                        self.result = result
                        AbsLogger.info("LegacyMigrationExport", message: "Export prepared with \(result.files) files")
                        call.resolve(["name": result.url.lastPathComponent, "files": result.files, "bytes": result.bytes])
                    case let .failure(error):
                        AbsLogger.error("LegacyMigrationExport", message: "Export failed")
                        call.reject(LegacyExportJob.message(for: error), "EXPORT_FAILED")
                    }
                }
            }
        }
    }

    /// Hands the package to the system exporter as a copy, so the user picks a Files location
    /// (such as On My iPhone) and nothing is uploaded on the app's behalf.
    @objc func saveArchive(_ call: CAPPluginCall) {
        queue.async {
            guard let url = self.result?.url, !self.running else {
                call.reject("Prepare the export first.", "NO_EXPORT")
                return
            }
            DispatchQueue.main.async {
                guard self.pendingSave == nil, let presenter = self.bridge?.viewController else {
                    call.reject("The save dialog is not available right now.", "SAVE_UNAVAILABLE")
                    return
                }
                let picker = UIDocumentPickerViewController(forExporting: [url], asCopy: true)
                picker.delegate = self
                self.pendingSave = call
                presenter.present(picker, animated: true)
            }
        }
    }

    @objc func discardArchive(_ call: CAPPluginCall) {
        queue.async {
            guard !self.running else {
                call.reject("An export is in progress.", "EXPORT_RUNNING")
                return
            }
            self.result = nil
            do {
                try self.job.discard()
                call.resolve()
            } catch {
                call.reject(LegacyExportJob.message(for: error), "DISCARD_FAILED")
            }
        }
    }

    public func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        pendingSave?.resolve(["saved": !urls.isEmpty])
        pendingSave = nil
    }

    public func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        pendingSave?.resolve(["saved": false])
        pendingSave = nil
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
