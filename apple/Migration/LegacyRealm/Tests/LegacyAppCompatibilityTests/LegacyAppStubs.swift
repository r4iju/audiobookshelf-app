import Foundation
import RealmSwift

// The app types the legacy model sources call into, reduced to what those sources use. The
// models themselves are the legacy app's own files (LegacyAppModels links to ios/App/Shared/models).

enum AbsDownloader {
    static var documents = FileManager.default.temporaryDirectory

    static func itemDownloadFolder(path: String) -> URL? {
        documents.appendingPathComponent(path)
    }
}

final class Database {
    static let shared = Database()

    func getLocalFile(localFileId: String) -> LocalFile? {
        try? Realm().object(ofType: LocalFile.self, forPrimaryKey: localFileId)
    }

    func getLocalMediaProgress(localMediaProgressId: String) -> LocalMediaProgress? {
        try? Realm().object(ofType: LocalMediaProgress.self, forPrimaryKey: localMediaProgressId)
    }

    func getLocalLibraryItem(localLibraryItemId: String) -> LocalLibraryItem? {
        try? Realm().object(ofType: LocalLibraryItem.self, forPrimaryKey: localLibraryItemId)
    }
}

enum Store {
    static var serverConfig: ServerConnectionConfig?
}

// From Shared/util/Extensions.swift, which cannot be compiled here because it imports Capacitor.
extension KeyedDecodingContainer {
    func doubleOrStringDecoder(key: KeyedDecodingContainer<K>.Key) throws -> Double {
        do {
            return try decode(Double.self, forKey: key)
        } catch {
            let stringValue = try decode(String.self, forKey: key)
            return Double(stringValue) ?? 0.0
        }
    }

    func intOrStringDecoder(key: KeyedDecodingContainer<K>.Key) throws -> Int {
        do {
            return try decode(Int.self, forKey: key)
        } catch {
            let stringValue = try decode(String.self, forKey: key)
            return Int(stringValue) ?? 0
        }
    }

    func decode<T: Decodable>(_ type: Persisted<List<T>>.Type, forKey key: Key) throws -> Persisted<List<T>> {
        try decodeIfPresent(type, forKey: key) ?? Persisted<List<T>>(wrappedValue: List<T>())
    }
}

// From Shared/player/AudioPlayer.swift, which needs the player.
enum PlayMethod: Int {
    case directplay = 0
    case directstream = 1
    case transcode = 2
    case local = 3
}

#if os(macOS)
// PlaybackSession reads the vendor identifier when building a sync payload, never while persisting.
final class UIDevice {
    static let current = UIDevice()
    let identifierForVendor: UUID? = nil
}
#endif

// From App/plugins/AbsDatabase.swift and AbsDownloader.swift, which are Capacitor plugins.
extension String {
    func toBase64() -> String {
        Data(self.utf8).base64EncodedString()
    }
}

enum LibraryItemDownloadError: String, Error {
    case podcastOnlySupported = "Only podcasts are supported for this function"
    case downloadItemPartNotFound = "DownloadItemPart not found"
    case downloadItemPartDestinationUrlNotDefined = "DownloadItemPart destination URL not defined"
}
