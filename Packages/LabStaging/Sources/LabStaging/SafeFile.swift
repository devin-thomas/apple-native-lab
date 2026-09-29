import Darwin
import Foundation

/// Low-level file operations that do not follow links where a link would let content escape.
///
/// Errors carry an `errno` value only, never a path.
enum SafeFile {
    enum Kind: Equatable {
        case regular
        case directory
        case symbolicLink
        case other
    }

    enum Failure: Error, Equatable {
        case missing
        /// A symbolic link where a file was expected, or a file with more than one hard link.
        case linked
        case notRegularFile
        case system(Int32)
    }

    /// The file-system path of `url` without a trailing slash. A trailing slash would make
    /// `lstat` and `O_NOFOLLOW` resolve a link in the last component instead of refusing it.
    static func path(_ url: URL) -> String {
        var path = url.path(percentEncoded: false)
        while path.count > 1, path.hasSuffix("/") { path.removeLast() }
        return path
    }

    /// What is at `url`, without following a link at its last component, or `nil` if nothing.
    static func kind(of url: URL) -> Kind? {
        var status = stat()
        guard lstat(path(url), &status) == 0 else { return nil }
        switch status.st_mode & S_IFMT {
        case S_IFREG: return .regular
        case S_IFDIR: return .directory
        case S_IFLNK: return .symbolicLink
        default: return .other
        }
    }

    /// The canonical path with every link resolved, or `nil` if it does not exist.
    static func resolvedPath(of url: URL) -> String? {
        guard let resolved = realpath(path(url), nil) else { return nil }
        defer { free(resolved) }
        return String(cString: resolved)
    }

    /// Opens a regular file inside staging for reading. The last component must not be a
    /// symbolic link (`O_NOFOLLOW`), and the file must have exactly one hard link, so it cannot
    /// be another location's file in disguise. The checks run on the open descriptor, so the
    /// file cannot be swapped between check and use.
    static func openStagedFile(_ url: URL) throws(Failure) -> (handle: FileHandle, size: Int) {
        let descriptor = open(path(url), O_RDONLY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK)
        guard descriptor >= 0 else {
            switch errno {
            case ENOENT: throw .missing
            case ELOOP: throw .linked
            default: throw .system(errno)
            }
        }
        var status = stat()
        guard fstat(descriptor, &status) == 0 else {
            let code = errno
            close(descriptor)
            throw .system(code)
        }
        guard status.st_mode & S_IFMT == S_IFREG else {
            close(descriptor)
            throw .notRegularFile
        }
        guard status.st_nlink == 1 else {
            close(descriptor)
            throw .linked
        }
        return (FileHandle(fileDescriptor: descriptor, closeOnDealloc: true), Int(status.st_size))
    }

    /// Opens a file a person chose, for reading. A link to it is fine, since the person chose
    /// it, but it must be an ordinary file: a pipe or device could block or never end.
    static func openSource(_ url: URL) throws(Failure) -> (handle: FileHandle, size: Int) {
        let descriptor = open(path(url), O_RDONLY | O_CLOEXEC | O_NONBLOCK)
        guard descriptor >= 0 else { throw errno == ENOENT ? .missing : .system(errno) }
        var status = stat()
        guard fstat(descriptor, &status) == 0, status.st_mode & S_IFMT == S_IFREG else {
            close(descriptor)
            throw .notRegularFile
        }
        return (FileHandle(fileDescriptor: descriptor, closeOnDealloc: true), Int(status.st_size))
    }

    /// Creates a new file for writing. Fails if anything, including a link, is already there.
    static func createExclusively(_ url: URL) throws(Failure) -> FileHandle {
        let descriptor = open(path(url), O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard descriptor >= 0 else { throw .system(errno) }
        return FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
    }

    /// Renames a folder into place, failing rather than replacing anything already there.
    /// Returns `false` when the destination exists.
    static func moveExclusively(_ source: URL, to destination: URL) throws(Failure) -> Bool {
        let result = renamex_np(path(source), path(destination), UInt32(RENAME_EXCL))
        guard result == 0 else {
            if errno == EEXIST || errno == ENOTEMPTY { return false }
            throw .system(errno)
        }
        return true
    }
}
