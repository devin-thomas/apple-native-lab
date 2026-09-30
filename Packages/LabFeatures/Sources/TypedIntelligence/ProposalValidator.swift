import Foundation
import LabDomain

/// Decides, deterministically, what a draft may become.
///
/// Guided generation constrains the shape of the model's answer, not its truth. This validator
/// checks every field the same way whoever wrote it, the model, the sample parser, a person, or a
/// hostile test double: lengths, values, and cross-field rules. Only a proposal with no blocking
/// issue carries an operation, and that operation is always one `.updateItem` on one of the offered
/// samples, pinned to the revision that was read. No field can select another kind of operation.
public enum ProposalValidator {
    public static func validate(
        _ fields: ProposalFields,
        source: ProposalSource,
        editedByPerson: Bool = false,
        note: SourceNote,
        candidates: [SampleCandidate]
    ) -> ExtractionProposal {
        var issues: [ValidationIssue] = []

        // Values: the target must be exactly one offered sample.
        let target: SampleCandidate?
        switch fields.target {
        case .none:
            target = nil
            issues.append(.noSampleChosen)
        case .title(let name):
            let matches = candidates.filter { $0.title == name.trimmingCharacters(in: .whitespacesAndNewlines) }
            switch matches.count {
            case 0: target = nil; issues.append(.unknownSample)
            case 1: target = matches[0]
            default: target = nil; issues.append(.sampleNameMatchesSeveral(count: matches.count))
            }
        case .item(let id):
            target = candidates.first { $0.id == id }
            if target == nil { issues.append(.unknownSample) }
        }
        if let target, target.item.isArchived { issues.append(.sampleArchived) }

        // Lengths and characters.
        let title = fields.newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        var entityTitle: EntityTitle?
        if title.isEmpty {
            issues.append(.titleEmpty)
        } else if title.count > ProposalLimits.title {
            issues.append(.titleTooLong(limit: ProposalLimits.title))
        } else if title.unicodeScalars.contains(where: { $0.properties.generalCategory == .control }) {
            issues.append(.titleHasControlCharacters)
        } else {
            entityTitle = try? EntityTitle(title)
            if entityTitle == nil { issues.append(.titleHasControlCharacters) }
        }

        let added = fields.addedNote.trimmingCharacters(in: .whitespacesAndNewlines)
        var addedIsValid = true
        if added.count > ProposalLimits.addedNote {
            issues.append(.addedNoteTooLong(limit: ProposalLimits.addedNote))
            addedIsValid = false
        } else if added.unicodeScalars.contains(where: { $0.properties.generalCategory == .control && !["\n", "\t"].contains($0) }) {
            issues.append(.addedNoteHasControlCharacters)
            addedIsValid = false
        }

        // Cross-field rules against the sample as read.
        var newNote: ItemNote?
        var diff: SampleDiff?
        if let target {
            let current = target.item
            if addedIsValid, !added.isEmpty {
                let combined = current.note.value.isEmpty ? added : current.note.value + "\n" + added
                if let note = try? ItemNote(combined) {
                    newNote = note
                } else {
                    issues.append(.noteWouldBeTooLong(limit: ItemNote.maximumLength))
                    addedIsValid = false
                }
                if current.note.value.range(of: added, options: [.caseInsensitive, .diacriticInsensitive]) != nil {
                    issues.append(.addedNoteAlreadyPresent)
                }
            }
            if let entityTitle, addedIsValid, entityTitle == current.title, newNote == nil {
                issues.append(.noChange)
            }
            diff = SampleDiff(
                titleBefore: current.title.value,
                titleAfter: entityTitle?.value ?? title,
                noteBefore: current.note.value,
                noteAfter: newNote?.value ?? current.note.value
            )
        }

        // Evidence: kept only when it is in the note word for word.
        var evidence: [EvidenceSpan] = []
        var dropped = 0
        for quote in fields.evidence {
            let trimmed = quote.trimmingCharacters(in: .whitespacesAndNewlines)
            guard evidence.count < ProposalLimits.evidenceCount,
                  ProposalLimits.evidenceLength.contains(trimmed.count),
                  let range = note.text.range(of: trimmed),
                  !evidence.contains(where: { $0.quote == trimmed })
            else {
                dropped += 1
                continue
            }
            evidence.append(EvidenceSpan(quote: trimmed, offset: note.text.distance(from: note.text.startIndex, to: range.lowerBound)))
        }
        if dropped > 0 { issues.append(.evidenceNotInNote(count: dropped)) }
        if evidence.isEmpty, source != .manualEditor { issues.append(.noEvidence) }

        // Other samples the note could mean: offered samples only, never the target itself.
        var others: [SampleCandidate] = []
        for name in fields.otherPossibleSamples.prefix(ProposalLimits.otherSamples) {
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let match = candidates.first(where: { $0.title == trimmed }), match.id != target?.id,
                  !others.contains(match) else { continue }
            others.append(match)
        }
        if !others.isEmpty { issues.append(.otherPossibleSamples(others.map(\.title))) }
        // Cross-check: samples the note names outright that the draft left out. A draft can be
        // well formed and confident about the wrong sample; this rule does not decide which is
        // right, it makes sure the person sees every sample the note names.
        let named = SampleParser.mentions(in: note.text, candidates: candidates)
            .filter { $0.id != target?.id && !others.contains($0) }
        if !named.isEmpty { issues.append(.noteNamesOtherSamples(named.map(\.title))) }

        var operation: DomainOperation?
        if !issues.contains(where: \.isBlocking), let target, let entityTitle {
            let changedTitle = entityTitle == target.item.title ? nil : entityTitle
            if let changes = try? ItemChanges(title: changedTitle, note: newNote) {
                operation = .updateItem(id: target.id, expected: target.item.revision, changes: changes)
            } else {
                issues.append(.noChange)
            }
        }

        return ExtractionProposal(
            source: source,
            editedByPerson: editedByPerson,
            target: target,
            newTitle: title,
            addedNote: added,
            evidence: evidence,
            otherPossibleSamples: others,
            issues: issues,
            diff: diff,
            operation: operation
        )
    }
}
