import Foundation
import LabDomain

/// The experiment's own folder: finished renders in `Output`, and one work folder per job in
/// `Work`, both on one volume so publishing is a single rename.
///
/// Everything here belongs to the experiment. Reset Demo removes the whole folder, and nothing
/// outside it is ever read or written.
public struct RenderWorkspace: Hashable, Sendable {
    public let root: URL

    public init(root: URL) {
        self.root = root
    }

    /// `Application Support/<folder>/Render That Survives` in the app's own container.
    public static func appSupport(folder: String) throws -> RenderWorkspace {
        let support = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        )
        return RenderWorkspace(root: support
            .appending(path: folder, directoryHint: .isDirectory)
            .appending(path: "Render That Survives", directoryHint: .isDirectory))
    }

    public var outputFolder: URL { root.appending(path: "Output", directoryHint: .isDirectory) }
    var workRoot: URL { root.appending(path: "Work", directoryHint: .isDirectory) }

    public func output(for recipe: RenderRecipe) -> URL {
        outputFolder.appending(path: recipe.outputName, directoryHint: .notDirectory)
    }

    func workFolder(for job: JobID) -> URL {
        workRoot.appending(path: job.rawValue.uuidString, directoryHint: .isDirectory)
    }

    func segment(_ index: Int, of job: JobID) -> URL {
        workFolder(for: job).appending(path: String(format: "segment-%03d.mov", index), directoryHint: .notDirectory)
    }

    func assembled(for job: JobID) -> URL {
        workFolder(for: job).appending(path: "assembled.partial.mov", directoryHint: .notDirectory)
    }

    /// Removes a job's work folder: its segments and any partial file.
    public func discardWork(of job: JobID) {
        try? FileManager.default.removeItem(at: workFolder(for: job))
    }

    /// Removes partial files a stopped run left in a job's work folder, keeping finished segments.
    func discardPartials(of job: JobID) {
        let folder = workFolder(for: job)
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path(percentEncoded: false))) ?? []
        for name in names where name.contains(".partial.") {
            try? FileManager.default.removeItem(at: folder.appending(path: name, directoryHint: .notDirectory))
        }
    }

    /// Removes every work folder that does not belong to one of `keep`, and every partial file in
    /// the output folder. Returns how many entries it removed.
    @discardableResult
    public func sweep(keeping keep: Set<JobID>) -> Int {
        let manager = FileManager.default
        var removed = 0
        let workNames = (try? manager.contentsOfDirectory(atPath: workRoot.path(percentEncoded: false))) ?? []
        for name in workNames {
            if let id = UUID(uuidString: name), keep.contains(JobID(rawValue: id)) { continue }
            if (try? manager.removeItem(at: workRoot.appending(path: name))) != nil { removed += 1 }
        }
        let outputNames = (try? manager.contentsOfDirectory(atPath: outputFolder.path(percentEncoded: false))) ?? []
        for name in outputNames where name.contains(".partial.") || name.hasPrefix(".") {
            if (try? manager.removeItem(at: outputFolder.appending(path: name))) != nil { removed += 1 }
        }
        return removed
    }

    /// Removes the experiment's whole folder (Reset Demo).
    public func removeEverything() {
        try? FileManager.default.removeItem(at: root)
    }

    /// The names of the files in the output folder, sorted.
    public func outputNames() -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: outputFolder.path(percentEncoded: false))) ?? []).sorted()
    }
}
