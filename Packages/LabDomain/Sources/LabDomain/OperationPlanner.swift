/// What one operation would do to the current state, decided without writing anything.
struct OperationPlan: Sendable {
    var conflict: RevisionConflict?
    var changes: [EntityChange] = []
    var preconditions: [RevisionPrecondition] = []
    var collections: [LabCollection] = []
    var items: [LabItem] = []
    var sessions: [LabSession] = []
    var attentions: [LabAttention] = []
    var jobs: [LabJob] = []
    var anchors: [LabAnchor] = []
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
            let created = LabItem(
                id: draft.id, collectionID: parent.id, title: draft.title, note: draft.note, extras: draft.extras
            )
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

        case .setSession(let id, let expected, let running):
            return try await setSession(id, expected: expected, running: running)
        case .scheduleAttention(let expected, let draft):
            return try await scheduleAttention(expected: expected, draft: draft)
        case .cancelLabAlerts(let pins):
            return try await cancelLabAlerts(pins)
        case .restoreLabAlerts(let drafts):
            return try await restoreLabAlerts(drafts)

        case .startJob(let draft):
            return try await startJob(draft)

        case .updateJob(let id, let expected, let transition):
            return try await updateJob(id, expected: expected, transition: transition)

        case .placeAnchor(let draft):
            return try await placeAnchor(draft)

        case .moveAnchor(let id, let expected, let pose):
            return try await moveAnchor(id, expected: expected, to: pose)

        case .removeAnchor(let id, let expected):
            return try await removeAnchor(id, expected: expected)
        }
    }

    // MARK: Jobs (LAB-032 Render That Survives)

    /// Plans a new running job with none of its work durable yet.
    private func startJob(_ draft: JobDraft) async throws(OperationError) -> OperationPlan {
        let reference = EntityReference.job(draft.id)
        guard try await job(draft.id) == nil else { throw .ruleViolation(.alreadyExists(reference)) }
        let progress: JobProgress
        do { progress = try JobProgress(completed: 0, total: draft.total) } catch { throw .invalidPayload(error) }
        let created = LabJob(
            id: draft.id, jobKind: draft.kind, title: draft.title, progress: progress, namespace: draft.namespace
        )
        return OperationPlan(
            changes: [EntityChange(entity: reference, previousRevision: nil, newRevision: created.revision)],
            preconditions: [RevisionPrecondition(entity: reference, expected: nil)],
            jobs: [created],
            undo: nil,
            phrase: Phrase("Started", "Start", "\(draft.kind) job “\(draft.title)”")
        )
    }

    /// Plans one lifecycle step. A stale revision gets a conflict receipt, as every update does, so
    /// a worker that lost a race with a person's cancel learns it and stops. A finished job, a
    /// step the current phase does not allow, and progress that would not move forward are refused
    /// before anything is recorded.
    private func updateJob(_ id: JobID, expected: Revision, transition: JobTransition) async throws(OperationError) -> OperationPlan {
        let current = try await requireJob(id)
        if let conflict = conflict(current.reference, current.title, current.revision, expected) { return conflict }
        guard !current.phase.isFinished else { throw .ruleViolation(.jobFinished(id)) }
        let subject = "\(current.jobKind) job “\(current.title)”"
        let phase = current.phase.name

        func require(_ allowed: Set<JobPhase.Name>) throws(OperationError) {
            guard allowed.contains(phase) else { throw .ruleViolation(.jobPhase(id, current: phase)) }
        }

        let updated: LabJob
        let phrase: Phrase
        switch transition {
        case .checkpoint(let completed):
            try require([.running])
            guard completed != current.progress.completed else { throw .ruleViolation(.noChanges(current.reference)) }
            guard completed > current.progress.completed,
                  let progress = try? JobProgress(completed: completed, total: current.progress.total)
            else { throw .ruleViolation(.jobProgress(id)) }
            updated = current.revised(phase: .running, progress: progress)
            phrase = Phrase("Saved", "Save", "\(subject) at \(progress.phrase)")
        case .interrupt(let reason):
            try require([.running])
            updated = current.revised(phase: .interrupted(reason: reason))
            phrase = Phrase(
                past: "Stopped \(subject) at \(current.progress.phrase) because \(reason.clause). It can resume.",
                imperative: "Stop \(subject) at \(current.progress.phrase) because \(reason.clause)."
            )
        case .resume:
            try require([.interrupted])
            updated = current.revised(phase: .running)
            phrase = Phrase("Resumed", "Resume", "\(subject) from \(current.progress.phrase)")
        case .cancel:
            try require([.running, .interrupted])
            updated = current.revised(phase: .cancelled)
            phrase = Phrase("Cancelled", "Cancel", subject)
        case .fail(let failure):
            try require([.running, .interrupted])
            updated = current.revised(phase: .failed(failure: failure))
            phrase = Phrase(
                past: "\(subject.prefix(1).uppercased())\(subject.dropFirst()) failed: \(failure.message)",
                imperative: "Mark \(subject) as failed: \(failure.message)"
            )
        case .succeed(let output):
            try require([.running])
            let total = current.progress.total ?? current.progress.completed
            let progress = (try? JobProgress(completed: total, total: current.progress.total)) ?? current.progress
            updated = current.revised(phase: .succeeded(output: output), progress: progress)
            phrase = Phrase("Finished", "Finish", "\(subject) as “\(output.name)”")
        }
        return OperationPlan(
            changes: [EntityChange(entity: current.reference, previousRevision: current.revision, newRevision: updated.revision)],
            preconditions: [RevisionPrecondition(entity: current.reference, expected: current.revision)],
            jobs: [updated],
            undo: nil,
            phrase: phrase

        )
    }

    // MARK: Anchors (LAB-023 Tabletop Reality)

    /// Plans placing a new lab-owned anchor. It is created in the demo namespace at revision 1,
    /// and its undo removes it at that revision.
    private func placeAnchor(_ draft: AnchorDraft) async throws(OperationError) -> OperationPlan {
        let reference = EntityReference.anchor(draft.id)
        guard try await anchor(draft.id) == nil else { throw .ruleViolation(.alreadyExists(reference)) }
        let created = LabAnchor(id: draft.id, fixture: draft.fixture, title: draft.title, pose: draft.pose)
        return OperationPlan(
            changes: [EntityChange(entity: reference, previousRevision: nil, newRevision: created.revision)],
            preconditions: [RevisionPrecondition(entity: reference, expected: nil)],
            anchors: [created],
            undo: .removeAnchor(id: created.id, expected: created.revision),
            phrase: Phrase("Placed", "Place", "“\(draft.title)”")
        )
    }

    /// Plans moving or turning an anchor. A caller that saw an older revision gets a conflict
    /// receipt, so a stale nudge never lands on a pose the person did not see.
    private func moveAnchor(_ id: AnchorID, expected: Revision, to pose: AnchorPose) async throws(OperationError) -> OperationPlan {
        let current = try await requireAnchor(id)
        if let conflict = conflict(current.reference, current.title, current.revision, expected) { return conflict }
        guard current.pose != pose else { throw .ruleViolation(.noChanges(current.reference)) }
        let updated = current.revised(pose: pose)
        let (past, imperative) = pose.differsOnlyInYaw(from: current.pose) ? ("Turned", "Turn") : ("Moved", "Move")
        return OperationPlan(
            changes: [EntityChange(entity: current.reference, previousRevision: current.revision, newRevision: updated.revision)],
            preconditions: [RevisionPrecondition(entity: current.reference, expected: current.revision)],
            anchors: [updated],
            undo: .moveAnchor(id: id, expected: updated.revision, pose: current.pose),
            phrase: Phrase(past, imperative, "“\(current.title)”")
        )
    }

    /// Plans removing an anchor. The anchor is lab-owned, so the store deletes it; the undo places
    /// the same anchor, with the same ID, fixture, title, and pose, again.
    private func removeAnchor(_ id: AnchorID, expected: Revision) async throws(OperationError) -> OperationPlan {
        let current = try await requireAnchor(id)
        if let conflict = conflict(current.reference, current.title, current.revision, expected) { return conflict }
        return OperationPlan(
            preconditions: [RevisionPrecondition(entity: current.reference, expected: current.revision)],
            removals: [current.reference],
            undo: .placeAnchor(draft: current.draft),
            phrase: Phrase("Removed", "Remove", "“\(current.title)”")
        )
    }

    // MARK: Sessions (LAB-004 Surface Deck)

    /// Plans starting or pausing a session.
    ///
    /// A session that was never started is not stored and reads as paused, so the first start
    /// creates it at revision 1 and pausing it is a no-change. A caller that saw a stored session
    /// at an older revision gets a conflict receipt and nothing moves, which is how a stale widget
    /// or Control toggle reconciles instead of overwriting a newer change. A caller that saw no
    /// session when one now exists is refused as `alreadyExists`, the rule a creation follows.
    private func setSession(_ id: SessionID, expected: Revision?, running: Bool) async throws(OperationError) -> OperationPlan {
        let reference = EntityReference.session(id)
        let current = try await session(id)
        guard let current else {
            guard expected == nil else { throw .notFound(reference) }
            guard running else { throw .ruleViolation(.noChanges(reference)) }
            let created = LabSession(id: id, isRunning: true)
            return OperationPlan(
                changes: [EntityChange(entity: reference, previousRevision: nil, newRevision: created.revision)],
                preconditions: [RevisionPrecondition(entity: reference, expected: nil)],
                sessions: [created],
                undo: .setSession(id: id, expected: created.revision, running: false),
                phrase: Self.sessionPhrase(running: true)
            )
        }
        guard let expected else { throw .ruleViolation(.alreadyExists(reference)) }
        guard current.revision == expected else {
            let detail = "the demo session changed: expected revision \(expected), found \(current.revision)."
            return OperationPlan(
                conflict: RevisionConflict(entity: reference, expected: expected, current: current.revision),
                phrase: Phrase(past: "Not applied because \(detail)", imperative: "Out of date because \(detail)")
            )
        }
        guard current.isRunning != running else { throw .ruleViolation(.noChanges(reference)) }
        let updated = current.revised(isRunning: running)
        return OperationPlan(
            changes: [EntityChange(entity: reference, previousRevision: current.revision, newRevision: updated.revision)],
            preconditions: [RevisionPrecondition(entity: reference, expected: current.revision)],
            sessions: [updated],
            undo: .setSession(id: id, expected: updated.revision, running: current.isRunning),
            phrase: Self.sessionPhrase(running: running)
        )
    }

    // MARK: Lab alerts (LAB-043 Respectful Attention)

    /// Plans one consented lab alert. A matching stored alert is a no-change. A stale revision
    /// conflicts and writes nothing. The undo cancels that one alert.
    private func scheduleAttention(expected: Revision?, draft: AttentionDraft) async throws(OperationError) -> OperationPlan {
        let reference = EntityReference.attention(draft.id)
        let current = try await attention(draft.id)
        guard let current else {
            guard expected == nil else { throw .notFound(reference) }
            let created = LabAttention(draft)
            return OperationPlan(
                changes: [EntityChange(entity: reference, previousRevision: nil, newRevision: created.revision)],
                preconditions: [RevisionPrecondition(entity: reference, expected: nil)],
                attentions: [created],
                undo: .cancelLabAlerts(pins: [AttentionPin(id: draft.id, expected: created.revision)]),
                phrase: Self.attentionPhrase(draft, verb: ("Scheduled", "Schedule"))
            )
        }
        guard let expected else { throw .ruleViolation(.alreadyExists(reference)) }
        guard current.revision == expected else {
            let detail = "lab alert “\(current.reason)” changed: expected revision \(expected), found \(current.revision)."
            return OperationPlan(
                conflict: RevisionConflict(entity: reference, expected: expected, current: current.revision),
                phrase: Phrase(past: "Not applied because \(detail)", imperative: "Out of date because \(detail)")
            )
        }
        guard !current.matches(draft) else { throw .ruleViolation(.noChanges(reference)) }
        let updated = current.revised(draft)
        return OperationPlan(
            changes: [EntityChange(entity: reference, previousRevision: current.revision, newRevision: updated.revision)],
            preconditions: [RevisionPrecondition(entity: reference, expected: current.revision)],
            attentions: [updated],
            undo: .scheduleAttention(expected: updated.revision, draft: current.draftForUndo()),
            phrase: Self.attentionPhrase(draft, verb: ("Rescheduled", "Reschedule"))
        )
    }

    /// Removes only the named alerts. Any stored alert not named stays. An empty list changes nothing.
    private func cancelLabAlerts(_ pins: [AttentionPin]) async throws(OperationError) -> OperationPlan {
        guard !pins.isEmpty else { throw .ruleViolation(.nothingToCancel) }
        var seen = Set<AttentionID>()
        var matched: [LabAttention] = []
        for pin in pins {
            let reference = EntityReference.attention(pin.id)
            guard seen.insert(pin.id).inserted else { throw .ruleViolation(.alreadyExists(reference)) }
            guard let current = try await attention(pin.id) else { throw .notFound(reference) }
            guard current.revision == pin.expected else {
                let detail = "lab alert “\(current.reason)” changed: expected revision \(pin.expected), found \(current.revision)."
                return OperationPlan(
                    conflict: RevisionConflict(entity: reference, expected: pin.expected, current: current.revision),
                    phrase: Phrase(past: "Not applied because \(detail)", imperative: "Out of date because \(detail)")
                )
            }
            matched.append(current)
        }
        let drafts = matched.map { $0.draftForUndo() }
        let count = counted(matched.count, "lab alert")
        return OperationPlan(
            preconditions: matched.map { RevisionPrecondition(entity: $0.reference, expected: $0.revision) },
            removals: matched.map(\.reference),
            undo: .restoreLabAlerts(drafts: drafts),
            phrase: Phrase(past: "Cancelled \(count).", imperative: "Cancel \(count).")
        )
    }

    /// Restores alerts a cancel removed. Each one must be absent. The undo cancels them again.
    private func restoreLabAlerts(_ drafts: [AttentionDraft]) async throws(OperationError) -> OperationPlan {
        guard !drafts.isEmpty else { throw .ruleViolation(.nothingToCancel) }
        var seen = Set<AttentionID>()
        var created: [LabAttention] = []
        for draft in drafts {
            let reference = EntityReference.attention(draft.id)
            guard seen.insert(draft.id).inserted else { throw .ruleViolation(.alreadyExists(reference)) }
            guard try await attention(draft.id) == nil else { throw .ruleViolation(.alreadyExists(reference)) }
            created.append(LabAttention(draft))
        }
        let count = counted(created.count, "lab alert")
        return OperationPlan(
            changes: created.map { EntityChange(entity: $0.reference, previousRevision: nil, newRevision: $0.revision) },
            preconditions: created.map { RevisionPrecondition(entity: $0.reference, expected: nil) },
            attentions: created,
            undo: .cancelLabAlerts(pins: created.map { AttentionPin(id: $0.id, expected: $0.revision) }),
            phrase: Phrase(past: "Restored \(count).", imperative: "Restore \(count).")
        )
    }

    private static func attentionPhrase(_ draft: AttentionDraft, verb: (String, String)) -> Phrase {
        let when = draft.moment.label(deviceZone: draft.moment.timeZone)
        let object = "the lab \(draft.channel.title.lowercased()) “\(draft.reason)” for \(when)"
        return Phrase(verb.0, verb.1, object)
    }

    private static func sessionPhrase(running: Bool) -> Phrase {
        running
            ? Phrase("Started", "Start", "the demo session")
            : Phrase("Paused", "Pause", "the demo session")
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
                revision: current?.revision.next() ?? .initial, namespace: .demo,
                // Extras are never rewritten, by a reset either; the store keeps them in place too.
                extras: current?.extras ?? .empty
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

        // Demo jobs are experiment state outside the seed. They are removed, and the experiment
        // that ran one removes its own files when it sees the receipt. User jobs are never touched.
        for job in try await allJobs().filter({ $0.namespace == .demo }).sorted(by: { $0.id.rawValue.uuidString < $1.id.rawValue.uuidString }) {
            plan.preconditions.append(RevisionPrecondition(entity: job.reference, expected: job.revision))
            plan.removals.append(job.reference)
        }

        // Sessions are demo state outside the seed. A running one is paused at its next revision,
        // never removed, so a stale toggle prepared before the reset finds a newer revision.
        for session in try await allSessions().sorted(by: { $0.id.rawValue.uuidString < $1.id.rawValue.uuidString }) {
            plan.preconditions.append(RevisionPrecondition(entity: session.reference, expected: session.revision))
            guard session.isRunning else { continue }
            let paused = session.revised(isRunning: false)
            plan.sessions.append(paused)
            plan.changes.append(EntityChange(entity: session.reference, previousRevision: session.revision, newRevision: paused.revision))
        }

        // Lab alerts are demo state outside the seed. Reset Demo removes them and nothing else
        // that a person keeps: user collections and items are not in this list.
        for attention in try await allAttentions().sorted(by: { $0.id.rawValue.uuidString < $1.id.rawValue.uuidString }) {
            plan.preconditions.append(RevisionPrecondition(entity: attention.reference, expected: attention.revision))
            plan.removals.append(attention.reference)
        }

        // Anchors are lab-owned placements outside the seed (LAB-023). A reset removes every one.
        let anchors = try await allAnchors().sorted { $0.id.rawValue.uuidString < $1.id.rawValue.uuidString }
        for anchor in anchors {
            plan.preconditions.append(RevisionPrecondition(entity: anchor.reference, expected: anchor.revision))
            plan.removals.append(anchor.reference)
        }

        let removedJobs = plan.removals.count(where: { $0.kind == .job })
        plan.phrase = resetPhrase(
            seed, changes: plan.changes, removed: plan.removals.count - removedJobs - anchors.count,
            removedJobs: removedJobs, anchors: anchors.count
        )
        return plan
    }

    private static func byID(_ lhs: (EntityReference, Revision), _ rhs: (EntityReference, Revision)) -> Bool {
        lhs.0.rawID.uuidString < rhs.0.rawID.uuidString
    }

    private func resetPhrase(_ seed: DemoSeed, changes: [EntityChange], removed: Int, removedJobs: Int, anchors: Int) -> Phrase {
        let contents = "\(counted(seed.collections.count, "collection")) and \(counted(seed.items.count, "item"))"
        // A reset only ever pauses a session, so session changes are counted apart from samples.
        let paused = changes.filter { $0.entity.kind == .session }.count
        let samples = changes.filter { $0.entity.kind != .session }
        let added = samples.filter { $0.previousRevision == nil }.count
        let restored = samples.count - added
        guard added + restored + removed + paused + removedJobs + anchors > 0 else {
            return Phrase(
                past: "The demo already matched its original \(contents).",
                imperative: "The demo already matches its original \(contents)."
            )
        }
        func tally(_ verbs: (String, String, String, String, String)) -> String {
            let counts = [(verbs.0, added), (verbs.1, restored), (verbs.2, removed)]
                .filter { $0.1 > 0 }
                .map { "\($0.0) \($0.1)" }
            let sessions = paused > 0 ? ["\(verbs.3) \(counted(paused, "session"))"] : []
            // Jobs are counted apart from samples, as sessions are (LAB-032).
            let jobs = removedJobs > 0 ? ["\(verbs.2) \(counted(removedJobs, "job"))"] : []
            // Placed anchors are counted apart from samples too: they are placements, not samples.
            let placed = anchors > 0 ? ["\(verbs.4) \(counted(anchors, "placed object"))"] : []
            return (counts + sessions + jobs + placed).joined(separator: ", ")
        }
        return Phrase(
            past: "Reset the demo to its original \(contents): \(tally(("added", "restored", "removed", "paused", "cleared"))).",
            imperative: "Reset the demo to its original \(contents): \(tally(("add", "restore", "remove", "pause", "clear")))."
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

    private func session(_ id: SessionID) async throws(OperationError) -> LabSession? {
        do { return try await store.session(id) } catch { throw .storeFailure(.readFailed) }
    }

    private func allSessions() async throws(OperationError) -> [LabSession] {
        do { return try await store.sessions() } catch { throw .storeFailure(.readFailed) }
    }

    private func attention(_ id: AttentionID) async throws(OperationError) -> LabAttention? {
        do { return try await store.attention(id) } catch { throw .storeFailure(.readFailed) }
    }

    private func allAttentions() async throws(OperationError) -> [LabAttention] {
        do { return try await store.attentions() } catch { throw .storeFailure(.readFailed) }
    }

    private func job(_ id: JobID) async throws(OperationError) -> LabJob? {
        do { return try await store.job(id) } catch { throw .storeFailure(.readFailed) }
    }

    private func allJobs() async throws(OperationError) -> [LabJob] {
        do { return try await store.jobs() } catch { throw .storeFailure(.readFailed) }
    }

    private func requireJob(_ id: JobID) async throws(OperationError) -> LabJob {
        guard let job = try await job(id) else { throw .notFound(.job(id)) }
        return job
    }

    private func anchor(_ id: AnchorID) async throws(OperationError) -> LabAnchor? {
        do { return try await store.anchor(id) } catch { throw .storeFailure(.readFailed) }
    }

    private func allAnchors() async throws(OperationError) -> [LabAnchor] {
        do { return try await store.anchors() } catch { throw .storeFailure(.readFailed) }
    }

    private func requireAnchor(_ id: AnchorID) async throws(OperationError) -> LabAnchor {
        guard let anchor = try await anchor(id) else { throw .notFound(.anchor(id)) }
        return anchor
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
