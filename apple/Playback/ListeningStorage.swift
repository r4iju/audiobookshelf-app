import Foundation

/// Where listening, the record of sent progress and confirmed progress resets are kept between launches.
///
/// An Apple TV app has no persistent files. Apart from 500 KB of user defaults, everything it saves must be purgeable
/// (App Programming Guide for tvOS, "Local Storage for Your App Is Limited"), and Application Support cannot be written
/// on a device (#114). There the records are kept in user defaults; files that an earlier build left are only read.
/// The journal has 256 KB of that space (`ListeningJournal`), the record of sent progress 64 KB plus one 64 KB copy set
/// aside when it was unreadable, and the resets 16 KB: 400 KB, leaving room for the app's other defaults. The journal and
/// the resets set nothing aside; an unreadable one stops saving instead.
struct ListeningStorage {
    /// The folder of the saved files.
    let folder: URL
    /// Persistent user defaults that keep the saved records instead of files, or nil to keep files.
    let defaults: UserDefaults?

    static var standard: ListeningStorage {
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("NativeListening", isDirectory: true)
        #if os(tvOS)
        return ListeningStorage(folder: folder, defaults: .standard)
        #else
        return ListeningStorage(folder: folder, defaults: nil)
        #endif
    }

    var journalFile: URL { folder.appendingPathComponent("listening.json") }
    var publicationsFile: URL { folder.appendingPathComponent("publications.json") }
    var resetsFile: URL { folder.appendingPathComponent("progress-resets.json") }

    static let publicationsKey = "NativeListeningPublications"
    static let resetsKey = "NativeListeningResets"

    var publications: SavedRecord { SavedRecord(file: publicationsFile, defaults: defaults, key: Self.publicationsKey, maximumBytes: 64_000) }
    var resets: SavedRecord { SavedRecord(file: resetsFile, defaults: defaults, key: Self.resetsKey, maximumBytes: 16_000) }
}

/// One small saved document: a file, or a bounded user defaults value when `defaults` is set.
struct SavedRecord {
    let file: URL
    var defaults: UserDefaults?
    var key = ""
    var maximumBytes = Int.max

    /// The saved bytes, or nil when nothing was saved. With defaults, a file is read until the first save.
    func read() throws -> Data? {
        if let defaults, let stored = defaults.object(forKey: key) {
            guard let data = stored as? Data else { throw ListeningJournal.Failure.invalidData }
            return data
        }
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        return try Data(contentsOf: file)
    }

    func write(_ data: Data) throws {
        if let defaults {
            guard data.count <= maximumBytes else { throw ListeningJournal.Failure.storageFull }
            try Self.store(data, forKey: key, in: defaults)
            return
        }
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        var options: Data.WritingOptions = .atomic
        #if os(iOS) || os(tvOS)
        options.insert(.completeFileProtectionUntilFirstUserAuthentication)
        #endif
        try data.write(to: file, options: options)
    }

    /// Keeps bytes that could not be read beside the record, never replacing an earlier copy. Defaults hold one copy, so
    /// their space stays bounded; while it is taken this throws and the unreadable record stays in place.
    func setAside(_ data: Data, named name: String) throws {
        if let defaults {
            // Bytes read from an earlier build's file stay in that file, which is never rewritten here.
            guard defaults.object(forKey: key) != nil else { return }
            let aside = key + ".unreadable"
            guard defaults.object(forKey: aside) == nil else { throw CocoaError(.fileWriteFileExists) }
            guard data.count <= maximumBytes else { throw ListeningJournal.Failure.storageFull }
            try Self.store(data, forKey: aside, in: defaults)
            return
        }
        try data.write(to: file.deletingLastPathComponent().appendingPathComponent(name), options: .withoutOverwriting)
    }

    private static func store(_ data: Data, forKey key: String, in defaults: UserDefaults) throws {
        let previous = defaults.object(forKey: key)
        defaults.set(data, forKey: key)
        guard defaults.synchronize() else {
            if let previous { defaults.set(previous, forKey: key) } else { defaults.removeObject(forKey: key) }
            throw ListeningJournal.Failure.invalidData
        }
    }
}
