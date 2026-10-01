import CryptoKit
import Darwin
import Foundation

/// An inode's identity and change times when its content was hashed. Writing content always
/// moves the change time (which, unlike the modification time, cannot be set back), and
/// replacing the file changes the inode, so an equal stamp means the hashed content still holds.
struct FileStamp: Codable, Equatable {
    var device: Int64
    var inode: UInt64
    var size: Int64
    var modified: Int64
    var changed: Int64

    init(_ info: stat) {
        device = Int64(info.st_dev)
        inode = UInt64(info.st_ino)
        size = Int64(info.st_size)
        modified = Int64(info.st_mtimespec.tv_sec) * 1_000_000_000 + Int64(info.st_mtimespec.tv_nsec)
        changed = Int64(info.st_ctimespec.tv_sec) * 1_000_000_000 + Int64(info.st_ctimespec.tv_nsec)
    }
}

/// Regular files reached from a trusted directory through real directories only: no symbolic link,
/// at the leaf or above it, is followed.
enum ContainedFile {
    static func isRelative(_ path: String) -> Bool {
        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        return !path.isEmpty && !path.hasPrefix("/") && !components.contains { $0.isEmpty || $0 == "." || $0 == ".." }
    }

    /// `base/path` when every component below `base` is a directory and the last a regular file.
    static func url(_ path: String, under base: URL) -> URL? {
        guard isRelative(path) else { return nil }
        let components = path.split(separator: "/")
        var url = base
        for (index, component) in components.enumerated() {
            url.appendPathComponent(String(component))
            guard let type = type(at: url), type == (index == components.count - 1 ? S_IFREG : S_IFDIR) else { return nil }
        }
        return url
    }

    static func stamp(of url: URL) -> FileStamp? {
        var info = stat()
        guard lstat(url.path, &info) == 0, info.st_mode & S_IFMT == S_IFREG else { return nil }
        return FileStamp(info)
    }

    /// SHA-256 of a regular file, refusing a symbolic link. The stamp is taken before reading, so a
    /// change made while reading leaves a later stamp than the one returned.
    static func digest(of url: URL) throws -> (sha256: String, stamp: FileStamp) {
        let descriptor = open(url.path, O_RDONLY | O_NOFOLLOW)
        guard descriptor >= 0 else { throw CocoaError(.fileReadNoSuchFile, userInfo: [NSURLErrorKey: url]) }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        var info = stat()
        guard fstat(descriptor, &info) == 0, info.st_mode & S_IFMT == S_IFREG else { throw CocoaError(.fileReadCorruptFile, userInfo: [NSURLErrorKey: url]) }
        var hasher = SHA256()
        while true {
            let chunk = handle.readData(ofLength: 1 << 20)
            if chunk.isEmpty { break }
            hasher.update(data: chunk)
        }
        return (hasher.finalize().hex, FileStamp(info))
    }

    /// Clears the way to `base/path`: the first component below `base` that is not a real directory
    /// is removed (a symbolic link itself, never what it points at), as is anything at the leaf.
    /// With `creatingDirectories`, the directories leading to the leaf are then created.
    static func clear(_ path: String, under base: URL, creatingDirectories: Bool) throws {
        guard isRelative(path) else { throw CocoaError(.fileWriteInvalidFileName) }
        let components = path.split(separator: "/")
        var url = base
        for (index, component) in components.enumerated() {
            url.appendPathComponent(String(component))
            let isLeaf = index == components.count - 1
            let existing = type(at: url)
            if existing != nil && (isLeaf || existing != S_IFDIR) {
                try FileManager.default.removeItem(at: url)
            } else if existing == nil && !creatingDirectories {
                return
            }
            if !isLeaf && existing != S_IFDIR {
                guard creatingDirectories else { return }
                try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
            }
        }
    }

    private static func type(at url: URL) -> mode_t? {
        var info = stat()
        guard lstat(url.path, &info) == 0 else { return nil }
        return info.st_mode & S_IFMT
    }
}
