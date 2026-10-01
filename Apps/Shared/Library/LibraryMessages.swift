import LabDomain
import LabStore

/// Plain sentences for the library's failures. They name the smallest useful fact and say what
/// did not change; they never include a path, SQL, or record content.
enum LibraryMessages {
    static func describe(_ error: any Error) -> String {
        switch error {
        case let error as OperationError: describe(error)
        case let error as StoreError: describe(error)
        case let error as DemoSeedResource.LoadError: describe(error)
        default: "Something unexpected went wrong. Nothing was changed."
        }
    }

    static func describe(_ error: DemoSeedResource.LoadError) -> String {
        switch error {
        case .missing: "This build is missing its demo seed, so the demo cannot be created."
        case .rejected: "This build's demo seed failed validation, so nothing was written."
        }
    }

    static func describe(_ error: StoreError) -> String {
        switch error {
        case .cannotOpen(let code):
            "The lab store could not be opened (SQLite \(code)). Nothing was changed."
        case .notALabStore:
            "The file at the lab store's location is not a Native Lab store. It was left unchanged."
        case .newerSchema(let found, let supported):
            "The lab store was written by a newer build (schema \(found); this build reads up to \(supported)). It was left unchanged."
        case .migrationFailed(let version, let code):
            "Updating the lab store to schema \(version) failed (SQLite \(code)). It keeps its previous version."
        case .readFailed(let code):
            "Reading the lab store failed (SQLite \(code))."
        case .writeFailed(let code):
            "The change was not saved (SQLite \(code)). Nothing was written."
        case .interrupted:
            "The change was interrupted before it finished."
        case .corruptRecord:
            "A stored record could not be read back."
        case .namespaceViolation:
            "The store refused a change that would have crossed between demo and personal data. Nothing was written."
        }
    }

    static func describe(_ error: OperationError) -> String {
        switch error {
        case .invalidPayload:
            "The request was not valid, so nothing was changed."
        case .unauthorized(let denial):
            "The app is not allowed to \(denial.required.phrase) here. Nothing was changed."
        case .notFound(let entity):
            "That \(entity.kind.rawValue) no longer exists."
        case .requestIDReused:
            "That request was already used for a different change. Nothing was changed."
        case .ruleViolation(let violation):
            describe(violation)
        case .storeFailure(.readFailed):
            "Reading the lab store failed."
        case .storeFailure(.commitFailed):
            "The change was not saved. Nothing was written."
        case .storeFailure(.contention):
            "Other changes kept interfering, so nothing was written. Try again."
        }
    }

    private static func describe(_ violation: RuleViolation) -> String {
        switch violation {
        case .alreadyExists: "It already exists."
        case .alreadyArchived: "It is already archived."
        case .notArchived: "It is not archived."
        case .archived: "Restore it before changing it."
        case .collectionArchived: "Its collection is archived."
        case .demoCollection: "Demo collections hold only the samples. Add items to your own collection."
        case .noChanges: "Nothing would change."
        case .jobFinished: "That job has finished and cannot change."
        case .jobPhase(_, let current): "That job is \(current.rawValue), so it cannot take that step."
        case .jobProgress: "A job's progress only moves forward."
        }
    }
}

extension Permission {
    fileprivate var phrase: String {
        switch self {
        case .read: "read"
        case .propose: "propose changes"
        case .commit: "make changes"
        case .commitDestructive: "make destructive changes"
        }
    }
}
