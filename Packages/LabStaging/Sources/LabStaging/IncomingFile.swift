import Foundation
import Synchronization

/// A file offered for import: its untrusted name and a stream of its bytes.
///
/// The stream may be slow, as for a cloud-backed attachment, and staging checks for cancellation
/// between chunks. The name is validated as a `StagedPath` before any byte is read.
public struct IncomingFile: Sendable {
    public let name: String
    let chunks: @Sendable () -> AsyncThrowingStream<Data, any Error>

    public init(name: String, chunks: @escaping @Sendable () -> AsyncThrowingStream<Data, any Error>) {
        self.name = name
        self.chunks = chunks
    }

    /// Bytes already in memory, such as pasted data.
    public static func data(_ data: Data, name: String) -> IncomingFile {
        IncomingFile(name: name) {
            AsyncThrowingStream { continuation in
                var offset = 0
                while offset < data.count {
                    let end = min(offset + BoundedInflater.chunkSize, data.count)
                    continuation.yield(data.subdata(in: offset..<end))
                    offset = end
                }
                continuation.finish()
            }
        }
    }

    /// A file a person chose, read in 64 KiB chunks. It must be an ordinary file; a folder, pipe,
    /// or device is refused before it is read.
    public static func contents(of url: URL, name: String? = nil) -> IncomingFile {
        IncomingFile(name: name ?? url.lastPathComponent) {
            let reader = SourceReader(url: url)
            return AsyncThrowingStream(unfolding: { try reader.next() })
        }
    }
}

/// Why an incoming file's bytes could not be read. Staging maps it to a rejection for that file.
enum SourceError: Error {
    case notRegularFile
    case unreadable
}

/// Reads a chosen file sequentially. `AsyncThrowingStream(unfolding:)` calls `next()` one at a
/// time, and the mutex makes that ordering explicit.
private final class SourceReader: Sendable {
    private let url: URL
    private let state = Mutex<FileHandle?>(nil)

    init(url: URL) { self.url = url }

    func next() throws -> Data? {
        try state.withLock { handle -> Data? in
            if handle == nil {
                do {
                    handle = try SafeFile.openSource(url).handle
                } catch SafeFile.Failure.notRegularFile {
                    throw SourceError.notRegularFile
                } catch {
                    throw SourceError.unreadable
                }
            }
            do {
                guard let data = try handle?.read(upToCount: BoundedInflater.chunkSize), !data.isEmpty else { return nil }
                return data
            } catch {
                throw SourceError.unreadable
            }
        }
    }
}
