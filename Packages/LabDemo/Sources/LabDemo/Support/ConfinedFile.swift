import Darwin
import Foundation
import LabDomain

/// Why a file could not be read from, or written below, a confined folder.
///
/// No case carries a path or a file name, so a refusal can be shown, logged, or exported without
/// revealing what was on disk.
public enum ConfinementError: Error, Hashable, Sendable {
    /// The relative name failed the import path policy (`StagedPath`): absolute, `..`, a
    /// lookalike separator, a control or invisible character, or too long.
    case invalidPath(PathRejection)
    /// The folder the name is relative to does not exist or is not a folder.
    case rootUnavailable
    case missing
    /// A component starts with `.` or carries the hidden flag. Hidden files are never exported.
    case hidden
    /// A symbolic link anywhere below the root, whether or not it points outside it.
    case symbolicLink
    /// A component other than the last is not a folder.
    case notAFolder
    /// The name is a folder, a device, a pipe, or anything but an ordinary file. A folder is never
    /// exported as a whole, so an adjacent file cannot come along with it.
    case notARegularFile
    /// The file has more than one hard link, so it may be another location's file in disguise.
    case hardLinked
    /// The opened file is not below the root, for example because a folder was swapped for a link
    /// after it was checked.
    case escapesRoot
    case tooLarge(limit: Int)
    /// The file's size changed while it was read.
    case changedWhileReading
    /// Something already exists where a new file or folder was to be created.
    case alreadyExists
    case system(Int32)
}

/// File operations confined to one root folder.
///
/// The root is the caller's trusted choice and is resolved once. Every name below it must pass
/// LabDomain's import path policy (`StagedPath`), every component is checked without following
/// links, and the file is opened with `O_NOFOLLOW` and checked again on its descriptor, so what is
/// read is the ordinary, singly linked, visible file the name promises, and it is inside the root.
enum ConfinedFile {
    /// The canonical path of `root`, which must be an existing folder.
    static func resolvedRoot(_ root: URL) throws(ConfinementError) -> String {
        guard let resolved = realpath(fileSystemPath(root), nil) else { throw .rootUnavailable }
        defer { free(resolved) }
        let path = String(cString: resolved)
        var status = stat()
        guard lstat(path, &status) == 0, status.st_mode & S_IFMT == S_IFDIR else { throw .rootUnavailable }
        return path
    }

    static func validatedPath(_ raw: String) throws(ConfinementError) -> StagedPath {
        do { return try StagedPath(raw) } catch { throw .invalidPath(error) }
    }

    /// Reads one ordinary file below `root`, at most `maximumBytes` long.
    static func read(_ relative: StagedPath, under root: URL, maximumBytes: Int) throws(ConfinementError) -> Data {
        let rootPath = try resolvedRoot(root)
        let filePath = try walk(relative, below: rootPath)
        return try readChecked(atPath: filePath, below: rootPath, maximumBytes: maximumBytes)
    }

    /// Checks every component of `relative` below `rootPath` without following links, and
    /// returns the file's path.
    static func walk(_ relative: StagedPath, below rootPath: String) throws(ConfinementError) -> String {
        var current = rootPath
        for (index, component) in relative.components.enumerated() {
            guard !component.hasPrefix(".") else { throw .hidden }
            current += "/" + component
            var status = stat()
            guard lstat(current, &status) == 0 else { throw errno == ENOENT ? .missing : .system(errno) }
            let isLast = index == relative.components.count - 1
            switch status.st_mode & S_IFMT {
            case S_IFLNK: throw .symbolicLink
            case S_IFDIR: if isLast { throw .notARegularFile }
            case S_IFREG: if !isLast { throw .notAFolder }
            default: throw isLast ? .notARegularFile : .notAFolder
            }
            guard status.st_flags & UInt32(UF_HIDDEN) == 0 else { throw .hidden }
        }
        return current
    }

    /// Opens and reads the file at `path`, repeating the checks on the open descriptor. A file or
    /// folder swapped for a link after `walk` checked it is refused: `O_NOFOLLOW` refuses a link
    /// in the last component, and the descriptor's own path must still be below `rootPath`.
    static func readChecked(atPath filePath: String, below rootPath: String, maximumBytes: Int) throws(ConfinementError) -> Data {
        let descriptor = open(filePath, O_RDONLY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK)
        guard descriptor >= 0 else {
            switch errno {
            case ENOENT: throw .missing
            case ELOOP: throw .symbolicLink
            default: throw .system(errno)
            }
        }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        var status = stat()
        guard fstat(descriptor, &status) == 0 else { throw .system(errno) }
        guard status.st_mode & S_IFMT == S_IFREG else { throw .notARegularFile }
        guard status.st_nlink == 1 else { throw .hardLinked }
        guard status.st_flags & UInt32(UF_HIDDEN) == 0 else { throw .hidden }
        guard status.st_size <= maximumBytes else { throw .tooLarge(limit: maximumBytes) }
        guard let opened = path(of: descriptor), isPath(opened, below: rootPath) else { throw .escapesRoot }

        let data: Data
        do { data = try handle.read(upToCount: maximumBytes + 1) ?? Data() } catch { throw .system(EIO) }
        guard data.count == Int(status.st_size) else { throw .changedWhileReading }
        return data
    }

    /// Creates a new folder. Fails if anything, including a link, is already there.
    static func makeFolder(atPath path: String) throws(ConfinementError) {
        guard mkdir(path, 0o755) == 0 else { throw errno == EEXIST ? .alreadyExists : .system(errno) }
    }

    /// Writes `data` to a new file at `relative` below the folder at `rootPath`, creating the
    /// intermediate folders. Nothing that already exists is replaced or followed.
    static func writeNew(_ data: Data, to relative: StagedPath, belowFolder rootPath: String) throws(ConfinementError) {
        var current = rootPath
        for component in relative.components.dropLast() {
            current += "/" + component
            if mkdir(current, 0o755) != 0 {
                guard errno == EEXIST else { throw .system(errno) }
                var status = stat()
                guard lstat(current, &status) == 0, status.st_mode & S_IFMT == S_IFDIR else { throw .notAFolder }
            }
        }
        current += "/" + (relative.components.last ?? "")
        let descriptor = open(current, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o644)
        guard descriptor >= 0 else { throw errno == EEXIST ? .alreadyExists : .system(errno) }
        defer { close(descriptor) }
        let written = data.withUnsafeBytes { buffer -> Bool in
            var offset = 0
            while offset < buffer.count {
                let result = Darwin.write(descriptor, buffer.baseAddress!.advanced(by: offset), buffer.count - offset)
                if result < 0 {
                    if errno == EINTR { continue }
                    return false
                }
                offset += result
            }
            return true
        }
        guard written, fsync(descriptor) == 0 else { throw .system(errno) }
    }

    /// Renames a folder into place, failing rather than replacing anything already there.
    static func moveExclusively(_ source: String, to destination: String) throws(ConfinementError) {
        guard renamex_np(source, destination, UInt32(RENAME_EXCL)) == 0 else {
            throw errno == EEXIST || errno == ENOTEMPTY ? .alreadyExists : .system(errno)
        }
    }

    /// Every entry below `rootPath`, relative to it, with whether it is an ordinary file. Links
    /// and special files are reported as not ordinary.
    static func inventory(below rootPath: String) -> [(path: String, isRegularFile: Bool, isFolder: Bool)] {
        guard let walker = FileManager.default.enumerator(atPath: rootPath) else { return [] }
        var entries: [(String, Bool, Bool)] = []
        while let relative = walker.nextObject() as? String {
            var status = stat()
            guard lstat(rootPath + "/" + relative, &status) == 0 else {
                entries.append((relative, false, false))
                continue
            }
            let kind = status.st_mode & S_IFMT
            entries.append((relative, kind == S_IFREG && status.st_nlink == 1, kind == S_IFDIR))
        }
        return entries
    }

    // MARK: Paths

    /// The file-system path of `url` without a trailing slash, so a link in the last component is
    /// examined rather than followed.
    static func fileSystemPath(_ url: URL) -> String {
        var path = url.path(percentEncoded: false)
        while path.count > 1, path.hasSuffix("/") { path.removeLast() }
        return path
    }

    private static func path(of descriptor: Int32) -> String? {
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        guard fcntl(descriptor, F_GETPATH, &buffer) != -1 else { return nil }
        return String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }

    /// Whether `path` is strictly below `root`. Both come from the file system in canonical form,
    /// so an exact comparison is the strict one: a mismatch refuses rather than admits.
    private static func isPath(_ path: String, below root: String) -> Bool {
        path.hasPrefix(root.hasSuffix("/") ? root : root + "/")
    }
}
