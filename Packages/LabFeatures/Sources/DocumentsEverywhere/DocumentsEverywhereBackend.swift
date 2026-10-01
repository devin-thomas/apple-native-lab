import Foundation
import LabDomain
import PortableObjects

/// What Documents Everywhere needs from the host for sensitive commits: the same
/// `OperationService` path the rest of the app uses (ADR-011, ADR-013).
///
/// Adopting a sample into the lab goes through `PortableObjectsImporter` (LAB-008), which stages,
/// validates, and commits as one create or update. This backend is the read/commit surface the
/// host's library already implements for Portable Objects.
public typealias DocumentsEverywhereBackend = PortableObjectsBackend

/// Adopts a catalog sample into the person's lab through Portable Objects' importer, so the
/// receipt joins the same authorization path as every other import.
public struct SampleAdopter: Sendable {
    private let importer: PortableObjectsImporter
    private let catalog: SampleCatalog

    public init(importer: PortableObjectsImporter, catalog: SampleCatalog = .bundled) {
        self.importer = importer
        self.catalog = catalog
    }

    /// Stages and reviews the sample, then commits it into `collectionID`. A cancelled task
    /// commits nothing. A sample the lab already holds is planned as Portable Objects plans it
    /// (nothing to import, or an update the person must apply).
    public func adopt(
        _ sampleID: ProviderItemID,
        into collectionID: CollectionID
    ) async throws(DocumentsEverywhereError) -> ImportResult {
        if Task.isCancelled { throw .cancelled }
        let data = try catalog.data(for: sampleID)
        if Task.isCancelled { throw .cancelled }
        do {
            let review = try await importer.review(data: data)
            if Task.isCancelled { throw DocumentsEverywhereError.cancelled }
            return try await importer.commit(review, into: collectionID)
        } catch is CancellationError {
            throw .cancelled
        } catch let error as PortableObjectError {
            throw DocumentsEverywhereError(error)
        } catch let error as DocumentsEverywhereError {
            throw error
        } catch {
            throw .unavailable
        }
    }
}

extension DocumentsEverywhereError {
    public init(_ error: PortableObjectError) {
        switch error {
        case .notALabObject: self = .notALabObject
        case .newerSchema(let found, let supported): self = .newerSchema(found: found, supported: supported)
        case .unsupportedSchema: self = .unsupportedSchema
        case .missingField(let field): self = .missingField(field.rawValue)
        case .invalidDocumentID: self = .invalidDocumentID
        case .invalidRevision: self = .invalidRevision
        case .cancelled: self = .cancelled
        case .notAuthorized: self = .notAuthorized
        case .storeUnavailable, .unavailable: self = .storeUnavailable
        case .nothingToImport: self = .invalidInput("This sample is already in the lab with the same content.")
        case .stateChanged, .changedSinceReview: self = .invalidInput("The lab changed while reviewing this sample.")
        default: self = .invalidInput("The sample could not be added.")
        }
    }

    public init(_ error: OperationError) {
        switch error {
        case .unauthorized: self = .notAuthorized
        case .notFound: self = .notFound
        case .storeFailure: self = .storeUnavailable
        case .invalidPayload: self = .invalidInput("The lab refused this change.")
        case .ruleViolation, .requestIDReused: self = .invalidInput("The lab refused this change.")
        }
    }
}
