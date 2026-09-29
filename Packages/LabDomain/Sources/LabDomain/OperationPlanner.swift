/// What one operation would do to the current state, decided without writing anything.
struct OperationPlan: Sendable {
    var conflict: RevisionConflict?
    var changes: [EntityChange] = []
    var preconditions: [RevisionPrecondition] = []
    var collections: [LabCollection] = []
    var items: [LabItem] = []
    var removals: [EntityReference] = []
    var undo: DomainOperation?
    var phrase: Phrase

    var status: ReceiptStatus {
        if let conflict { .conflict(conflict) } else { .committed }
    }
}

/// A receipt summary in the past tense and the matching proposal summary in the imperative.
struct Phrase: Sendable {
    let past: String
    let imperative: String

    init(past: String, imperative: String) {
        self.past = past
        self.imperative = imperative
    }

    init(_ pastVerb: String, _ imperativeVerb: String, _ object: String) {
        past = "\(pastVerb) \(object)."
        imperative = "\(imperativeVerb) \(object)."
    }
}

/// Validates an operation against the stored state and plans its writes, its receipt content, and
/// its inverse. The switch is exhaustive, so a new operation must decide its undo explicitly.
struct OperationPlanner: Sendable {
    let store: any OperationStore

    func plan(_ operation: DomainOperation) async throws(OperationError) -> OperationPlan {
        switch operation {
        case .createCollection(let draft):
            let reference = EntityReference.collection(draft.id)
            guard try await collection(draft.id) == nil else { throw .ruleViolation(.alreadyExists(reference)) }
            let created = LabCollection(id: draft.id, title: draft.title)
            return OperationPlan(
                changes: [EntityChange(entity: reference, previousRevision: nil, newRevision: created.revision)],
                preconditions: [RevisionPrecondition(entity: reference, expected: nil)],
                collections: [created],
                undo: .archiveCollection(id: created.id, expected: created.revision),
                phrase: Phrase("Created", "Create", "collection “\(draft.title)”")
            )

        case .updateCollection(let id, let expected, let title):
            let current = try await requireCollection(id)
            if let conflict = conflict(current.reference, current.title, current.revision, expected) { return conflict }
            guard !current.isArchived else { throw .ruleViolation(.archived(current.reference)) }
            guard current.title != title else { throw .ruleViolation(.noChanges(current.reference)) }
            let updated = current.revised(title: title)
            return change(
                current, updated,
                undo: .updateCollection(id: id, expected: updated.revision, title: current.title),
                phrase: Phrase("Renamed", "Rename", "collection “\(current.title)” to “\(title)”")
            )

        case .archiveCollection(let id, let expected):
            let current = try await requireCollection(id)
            if let conflict = conflict(current.reference, current.title, current.revision, expected) { return conflict }
            guard !current.isArchived else { throw .ruleViolation(.alreadyArchived(current.reference)) }
            let updated = current.revised(isArchived: true)
            return change(
                current, updated,
                undo: .restoreCollection(id: id, expected: updated.revision),
                phrase: Phrase("Archived", "Archive", "collection “\(current.title)”")
            )

        case .restoreCollection(let id, let expected):
            let current = try await requireCollection(id)
            if let conflict = conflict(current.reference, current.title, current.revision, expected) { return conflict }
            guard current.isArchived else { throw .ruleViolation(.notArchived(current.reference)) }
            let updated = current.revised(isArchived: false)
            return change(
                current, updated,
                undo: .archiveCollection(id: id, expected: updated.revision),
                phrase: Phrase("Restored", "Restore", "collection “\(current.title)”")
            )

        case .createItem(let draft):
            let reference = EntityReference.item(draft.id)
            guard try await item(draft.id) == nil else { throw .ruleViolation(.alreadyExists(reference)) }
            let parent = try await requireCollection(draft.collectionID)
            guard parent.namespace == .user else { throw .ruleViolation(.demoCollection(parent.id)) }
            guard !parent.isArchived else { throw .ruleViolation(.collectionArchived(parent.id)) }
            let created = LabItem(id: draft.id, collectionID: parent.id, title: draft.title, note: draft.note)
            return OperationPlan(
                changes: [EntityChange(entity: reference, previousRevision: nil, newRevision: created.revision)],
                // The parent is read, not written; pinning it stops a concurrent archive slipping in.
                preconditions: [
                    RevisionPrecondition(entity: reference, expected: nil),
                    RevisionPrecondition(entity: parent.reference, expected: parent.revision),
                ],
                items: [created],
                undo: .archiveItem(id: created.id, expected: created.revision),
                phrase: Phrase("Created", "Create", "item “\(draft.title)” in “\(parent.title)”")
            )

        case .updateItem(let id, let expected, let changes):
            let current = try await requireItem(id)
            if let conflict = conflict(current.reference, current.title, current.revision, expected) { return conflict }
            guard !current.isArchived else { throw .ruleViolation(.archived(current.reference)) }
            let newTitle = changes.title.flatMap { $0 == current.title ? nil : $0 }
            let newNote = changes.note.flatMap { $0 == current.note ? nil : $0 }
            guard newTitle != nil || newNote != nil else { throw .ruleViolation(.noChanges(current.reference)) }
            let updated = current.revised(title: newTitle, note: newNote)
            let inverse = ItemChanges(
                uncheckedTitle: newTitle == nil ? nil : current.title,
                note: newNote == nil ? nil : current.note
            )
            return change(
                current, updated,
                undo: .updateItem(id: id, expected: updated.revision, changes: inverse),
                phrase: itemUpdatePhrase(current, newTitle: newTitle, noteChanged: newNote != nil)
            )

        case .archiveItem(let id, let expected):
            let current = try await requireItem(id)
            if let conflict = conflict(current.reference, current.title, current.revision, expected) { return conflict }
            guard !current.isArchived else { throw .ruleViolation(.alreadyArchived(current.reference)) }
            let updated = current.revised(isArchived: true)
            return change(
                current, updated,
                undo: .restoreItem(id: id, expected: updated.revision),
                phrase: Phrase("Archived", "Archive", "item “\(current.title)”")
            )

        case .restoreItem(let id, let expected):
            let current = try await requireItem(id)
            if let conflict = conflict(current.reference, current.title, current.revision, expected) { return conflict }
            guard current.isArchived else { throw .ruleViolation(.notArchived(current.reference)) }
            let updated = current.revised(isArchived: false)
            return change(
                current, updated,
                undo: .archiveItem(id: id, expected: updated.revision),
                phrase: Phrase("Restored", "Restore", "item “\(current.title)”")
            )

        case .resetDemo(let seed):
            return try await resetDemo(to: seed)
        }
    }

    // MARK: Reset Demo

    /// Plans the writes that make the demo namespace equal `seed`.
    ///
    /// A sample that already matches the seed is not rewritten. A sample that differs gets the seed
    /// content at its next revision, never back at revision 1, so an operation prepared before the
    /// reset cannot silently apply to the restored sample. Every demo entity read is pinned by a
    /// precondition, and so is the absence of every sample still to be created, so any concurrent
    /// change makes the service plan again. User entities are never written or removed; a seed that
    /// names a user entity's identifier is refused.
    private func resetDemo(to seed: DemoSeed) async throws(OperationError) -> OperationPlan {
        let storedCollections = try await allCollections()
        let storedItems = try await allItems()
        let collectionsByID = Dictionary(storedCollections.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let itemsByID = Dictionary(storedItems.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var plan = OperationPlan(phrase: Phrase(past: "", imperative: ""))

        for draft in seed.collections {
            let reference = EntityReference.collection(draft.id)
            let current = collectionsByID[draft.id]
            if let current, current.namespace != .demo { throw .ruleViolation(.alreadyExists(reference)) }
            plan.preconditions.append(RevisionPrecondition(entity: reference, expected: current?.revision))
            if let current, current.title == draft.title, !current.isArchived { continue }
            let restored = LabCollection(
                id: draft.id, title: draft.title, revision: current?.revision.next() ?? .initial, namespace: .demo
            )
            plan.collections.append(restored)
            plan.changes.append(EntityChange(entity: reference, previousRevision: current?.revision, newRevision: restored.revision))
        }

        for draft in seed.items {
            let reference = EntityReference.item(draft.id)
            let current = itemsByID[draft.id]
            if let current, current.namespace != .demo { throw .ruleViolation(.alreadyExists(reference)) }
            plan.preconditions.append(RevisionPrecondition(entity: reference, expected: current?.revision))
            if let current, current.collectionID == draft.collectionID, current.title == draft.title,
               current.note == draft.note, !current.isArchived {
                continue
            }
            let restored = LabItem(
                id: draft.id, collectionID: draft.collectionID, title: draft.title, note: draft.note,
                revision: current?.revision.next() ?? .initial, namespace: .demo
            )
            plan.items.append(restored)
            plan.changes.append(EntityChange(entity: reference, previousRevision: current?.revision, newRevision: restored.revision))
        }

        // Demo entities the seed no longer names, items before the collections that held them.
        let seedCollectionIDs = Set(seed.collections.map(\.id))
        let seedItemIDs = Set(seed.items.map(\.id))
        let leftovers: [(EntityReference, Revision)] =
            storedItems.filter { $0.namespace == .demo && !seedItemIDs.contains($0.id) }
                .map { ($0.reference, $0.revision) }.sorted(by: Self.byID)
            + storedCollections.filter { $0.namespace == .demo && !seedCollectionIDs.contains($0.id) }
                .map { ($0.reference, $0.revision) }.sorted(by: Self.byID)
        for (reference, revision) in leftovers {
            plan.preconditions.append(RevisionPrecondition(entity: reference, expected: revision))
            plan.removals.append(reference)
        }

        plan.phrase = resetPhrase(seed, changes: plan.changes, removed: plan.removals.count)
        return plan
    }

    private static func byID(_ lhs: (EntityReference, Revision), _ rhs: (EntityReference, Revision)) -> Bool {
        lhs.0.rawID.uuidString < rhs.0.rawID.uuidString
    }

    private func resetPhrase(_ seed: DemoSeed, changes: [EntityChange], removed: Int) -> Phrase {
        let contents = "\(counted(seed.collections.count, "collection")) and \(counted(seed.items.count, "item"))"
        let added = changes.filter { $0.previousRevision == nil }.count
        let restored = changes.count - added
        guard added + restored + removed > 0 else {
            return Phrase(
                past: "The demo already matched its original \(contents).",
                imperative: "The demo already matches its original \(contents)."
            )
        }
        func tally(_ verbs: (String, String, String)) -> String {
            [(verbs.0, added), (verbs.1, restored), (verbs.2, removed)]
                .filter { $0.1 > 0 }
                .map { "\($0.0) \($0.1)" }
                .joined(separator: ", ")
        }
        return Phrase(
            past: "Reset the demo to its original \(contents): \(tally(("added", "restored", "removed"))).",
            imperative: "Reset the demo to its original \(contents): \(tally(("add", "restore", "remove")))."
        )
    }

    private func counted(_ count: Int, _ noun: String) -> String {
        "\(count) \(noun)\(count == 1 ? "" : "s")"
    }

    // MARK: Plans

    private func conflict(
        _ entity: EntityReference,
        _ title: EntityTitle,
        _ current: Revision,
        _ expected: Revision
    ) -> OperationPlan? {
        guard current != expected else { return nil }
        let detail = "\(entity.kind.rawValue) “\(title)” changed: expected revision \(expected), found \(current)."
        return OperationPlan(
            conflict: RevisionConflict(entity: entity, expected: expected, current: current),
            phrase: Phrase(past: "Not applied because \(detail)", imperative: "Out of date because \(detail)")
        )
    }

    private func change(
        _ before: LabCollection,
        _ after: LabCollection,
        undo: DomainOperation,
        phrase: Phrase
    ) -> OperationPlan {
        OperationPlan(
            changes: [EntityChange(entity: before.reference, previousRevision: before.revision, newRevision: after.revision)],
            preconditions: [RevisionPrecondition(entity: before.reference, expected: before.revision)],
            collections: [after],
            undo: undo,
            phrase: phrase
        )
    }

    private func change(_ before: LabItem, _ after: LabItem, undo: DomainOperation, phrase: Phrase) -> OperationPlan {
        OperationPlan(
            changes: [EntityChange(entity: before.reference, previousRevision: before.revision, newRevision: after.revision)],
            preconditions: [RevisionPrecondition(entity: before.reference, expected: before.revision)],
            items: [after],
            undo: undo,
            phrase: phrase
        )
    }

    private func itemUpdatePhrase(_ current: LabItem, newTitle: EntityTitle?, noteChanged: Bool) -> Phrase {
        switch (newTitle, noteChanged) {
        case (let title?, true):
            Phrase(
                past: "Renamed item “\(current.title)” to “\(title)” and updated its note.",
                imperative: "Rename item “\(current.title)” to “\(title)” and update its note."
            )
        case (let title?, false):
            Phrase("Renamed", "Rename", "item “\(current.title)” to “\(title)”")
        case (nil, _):
            Phrase("Updated", "Update", "the note of item “\(current.title)”")
        }
    }

    // MARK: Reads

    private func allCollections() async throws(OperationError) -> [LabCollection] {
        do { return try await store.collections() } catch { throw .storeFailure(.readFailed) }
    }

    private func allItems() async throws(OperationError) -> [LabItem] {
        do { return try await store.items(in: nil) } catch { throw .storeFailure(.readFailed) }
    }

    private func collection(_ id: CollectionID) async throws(OperationError) -> LabCollection? {
        do { return try await store.collection(id) } catch { throw .storeFailure(.readFailed) }
    }

    private func item(_ id: ItemID) async throws(OperationError) -> LabItem? {
        do { return try await store.item(id) } catch { throw .storeFailure(.readFailed) }
    }

    private func requireCollection(_ id: CollectionID) async throws(OperationError) -> LabCollection {
        guard let collection = try await collection(id) else { throw .notFound(.collection(id)) }
        return collection
    }

    private func requireItem(_ id: ItemID) async throws(OperationError) -> LabItem {
        guard let item = try await item(id) else { throw .notFound(.item(id)) }
        return item
    }
}
