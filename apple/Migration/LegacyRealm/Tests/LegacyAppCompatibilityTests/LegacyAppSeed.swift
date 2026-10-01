import Foundation
import RealmSwift

/// A synthetic library written with the legacy app's own model classes into the default Realm:
/// one connection carrying `token`, a downloaded book (audio and EPUB) with progress and an EPUB
/// location, an interrupted download whose part URL carries the token, and a log entry naming it.
struct LegacyAppSeed {
    var documents: URL
    var address: String
    var token: String
    var epub = Data("PK-app-epub".utf8)

    private func write(_ path: String, _ contents: Data) throws -> Int {
        let url = documents.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try contents.write(to: url)
        return contents.count
    }

    func write() throws {
        let audioSize = try write("li-1/01.mp3", Data("app-audio".utf8))
        let epubSize = try write("li-1/book.epub", epub)
        let partSize = try write("li-2/01.mp3", Data("app-finished-part".utf8))

        let realm = try Realm()
        try realm.write {
            let connection = ServerConnectionConfig()
            connection.id = "conn-1"
            connection.index = 1
            connection.name = "Synthetic"
            connection.address = address
            connection.version = "2.26.0"
            connection.userId = "user-1"
            connection.username = "reader"
            connection.token = token
            realm.add(connection)
            let active = ServerConnectionConfigActiveIndex()
            active.index = 1
            realm.add(active)
            let settings = DeviceSettings()
            settings.jumpForwardTime = 30
            realm.add(settings)

            let audio = LocalFile()
            audio.id = "lf-audio"
            audio.filename = "01.mp3"
            audio._contentUrl = "li-1/01.mp3"
            audio.mimeType = "audio/mpeg"
            audio.size = audioSize
            let epub = LocalFile()
            epub.id = "lf-epub"
            epub.filename = "book.epub"
            epub._contentUrl = "li-1/book.epub"
            epub.mimeType = "application/epub+zip"
            epub.size = epubSize
            let metadata = Metadata()
            metadata.title = "Synthetic Book"
            metadata.authorName = "Synthetic Author"
            let track = AudioTrack()
            track.index = 1
            track.startOffset = 0
            track.duration = 10
            track.mimeType = "audio/mpeg"
            track.localFileId = audio.id
            let ebookMetadata = FileMetadata()
            ebookMetadata.filename = "book.epub"
            ebookMetadata.ext = ".epub"
            let ebook = EBookFile()
            ebook.ino = "ino-epub"
            ebook.ebookFormat = "epub"
            ebook.metadata = ebookMetadata
            // As the app links a downloaded ebook (LocalLibraryItem.linkLocalFiles).
            _ = ebook.setLocalInfo(localFile: epub)
            let media = MediaType()
            media.libraryItemId = "li-1"
            media.metadata = metadata
            media.tracks.append(track)
            media.ebookFile = ebook
            let item = LocalLibraryItem()
            item.id = "local_li-1"
            item.libraryItemId = "li-1"
            item.mediaType = "book"
            item.basePath = "li-1"
            item._contentUrl = "li-1"
            item.serverConnectionConfigId = "conn-1"
            item.serverAddress = address
            item.serverUserId = "user-1"
            item.media = media
            item.localFiles.append(objectsIn: [audio, epub])
            realm.add(item)

            let progress = LocalMediaProgress()
            progress.id = "local_li-1"
            progress.localLibraryItemId = "local_li-1"
            progress.libraryItemId = "li-1"
            progress.serverConnectionConfigId = "conn-1"
            progress.serverAddress = address
            progress.serverUserId = "user-1"
            progress.currentTime = 42
            progress.duration = 10
            progress.ebookLocation = "epubcfi(/6/4!/4/2/1:0)"
            progress.ebookProgress = 0.3
            realm.add(progress)

            let part = DownloadItemPart()
            part.id = "part-1"
            part.downloadItemId = "dl-1"
            part.filename = "01.mp3"
            part.fileSize = Double(partSize)
            part.completed = true
            part.moved = true
            part.uri = "\(address)/api/items/li-2/file/1?token=\(token)"
            part.destinationUri = "li-2/01.mp3"
            let download = DownloadItem()
            download.id = "dl-1"
            download.libraryItemId = "li-2"
            download.serverConnectionConfigId = "conn-1"
            download.serverAddress = address
            download.serverUserId = "user-1"
            download.mediaType = "book"
            download.itemTitle = "Interrupted"
            download.downloadItemParts.append(part)
            realm.add(download)

            let log = LogEntry()
            log.message = "request failed for \(token)"
            realm.add(log)
        }
    }
}
