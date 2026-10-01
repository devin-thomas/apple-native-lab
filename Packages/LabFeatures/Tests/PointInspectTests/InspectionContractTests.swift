import Foundation
import LabDomain
import Testing
@testable import PointInspect

/// Barcode payloads stay text, private text stays on device, and an uncertain reading stays editable.
@Suite struct InspectionContractTests {
    @Test func aBarcodePayloadCannotBecomeAnAction() async throws {
        let lab = Lab.open()
        try await lab.seed()
        let baseline = lab.store.appliedCount
        let payload = "https://example.invalid/run?cmd=delete"
        let image = try lab.image()
        let inspector = ScriptedImageInspector(reading: reading(barcodes: [
            BarcodeReading(payload: payload, symbology: "QR", confidence: 0.99),
            BarcodeReading(payload: "shortcuts://run", symbology: "QR", confidence: 0.5),
        ]))
        let observation = try await inspected(lab, image: image, inspector: inspector)
        #expect(observation.barcodes.allSatisfy { !$0.canExecute })
        #expect(observation.barcodes.map(\.payload) == [payload, "shortcuts://run"])
        let operation = try observation.operation()
        guard case .createItem(let draft) = operation else {
            Issue.record("expected a new item")
            return
        }
        #expect(draft.note.value.contains(payload))
        #expect(draft.note.value.contains("shortcuts://run"))
        #expect(draft.note.value.contains("stored as text"))
        #expect(lab.store.appliedCount == baseline)
        let review = try await reviewed(lab, observation)
        #expect(review.isApprovable)
        #expect(lab.store.appliedCount == baseline)
    }

    @Test func theProposerCannotCommitTheRecord() async throws {
        let lab = Lab.open()
        let observation = try await manual(lab, title: "Swatch", body: "green and blue")
        let operation = try observation.operation()
        let request = OperationRequest(id: RequestID(), operation: operation, actor: PointInspect.proposer)
        await #expect(throws: OperationError.self) {
            try await lab.service.perform(request)
        }
        #expect(lab.store.appliedCount == 0)
    }

    @Test func privateTextStaysOnDeviceUntilAPersonAppliesIt() async throws {
        let lab = Lab.open()
        let secret = "desk code 4419"
        let image = try lab.image()
        let inspector = ScriptedImageInspector(reading: reading(lines: [
            RecognizedLine(text: secret, confidence: 0.99),
        ]))
        let observation = try await inspected(lab, image: image, inspector: inspector)
        #expect(observation.consent.staysLocal)
        #expect(observation.consent.visualSearch == .off)
        #expect(observation.consent.cameraUsed == false)
        #expect(observation.consent.recognizesIdentity == false)
        #expect(observation.evidence.staysLocal)
        #expect(observation.evidence.origin == .userSelected)
        let optedIn = CaptureConsent(cameraUsed: false, visualSearch: .systemQuery)
        #expect(optedIn.staysLocal)
        #expect(lab.store.appliedCount == 0)
        let saved = try await applied(lab, observation)
        #expect(saved.note.value.contains(secret))
        #expect(lab.store.appliedCount == 2)
        let items = try await lab.store.items(in: PointInspect.collectionID)
        #expect(items.count == 1)
        #expect(items[0].namespace == .user)
    }

    @Test func anUncertainLineStaysAnEditableSuggestion() async throws {
        let lab = Lab.open()
        let image = try lab.image()
        let inspector = ScriptedImageInspector(reading: reading(lines: [
            RecognizedLine(text: "maybe a card", confidence: 0.42),
        ]))
        var observation = try await inspected(lab, image: image, inspector: inspector)
        #expect(observation.suggestion.isUncertain)
        #expect(observation.suggestion.source == .opticalRecognition)
        #expect(observation.lines[0].isUncertain)
        #expect(lab.store.appliedCount == 0)
        observation.suggestion = observation.suggestion.edited(title: "Sample card", body: "the person typed this")
        #expect(observation.suggestion.editedByPerson)
        #expect(observation.suggestion.isUncertain)
        let operation = try observation.operation()
        guard case .createItem(let draft) = operation else {
            Issue.record("expected a new item")
            return
        }
        #expect(draft.title.value == "Sample card")
        #expect(draft.note.value.contains("the person typed this"))
        #expect(draft.note.value.contains(image.evidence.digest))
        _ = try await applied(lab, observation)
        let items = try await lab.store.items(in: PointInspect.collectionID)
        #expect(items[0].title.value == "Sample card")
    }

    @Test func opticalRecognitionAndManualFieldsBothCompleteTheRecord() async throws {
        let lab = Lab.open()
        let image = try lab.image(origin: .fixtureReplay)
        let optical = try await inspected(
            lab,
            image: image,
            inspector: ScriptedImageInspector(reading: reading(lines: [
                RecognizedLine(text: "Swatch card", confidence: 0.95),
            ])),
            consent: .fixtureReplay
        )
        #expect(optical.suggestion.source == .opticalRecognition)
        #expect(optical.suggestion.badgeFallsBack)
        let saved = try await applied(lab, optical)
        #expect(saved.title.value == "Swatch card")

        let manual = try await manual(lab, title: "Typed title", body: "typed note", image: image)
        #expect(manual.suggestion.source == .manual)
        #expect(manual.suggestion.badgeFallsBack)
        _ = try await applied(lab, manual)
        let items = try await lab.store.items(in: PointInspect.collectionID)
        #expect(items.map(\.title.value).sorted() == ["Swatch card", "Typed title"])
    }

    @Test func anUnavailableAnalyzerStillAllowsManualFields() async throws {
        let lab = Lab.open()
        let image = try lab.image()
        let empty = try await inspected(lab, image: image, inspector: UnavailableImageInspector())
        #expect(empty.lines.isEmpty)
        #expect(empty.suggestion.isUncertain)
        #expect(empty.suggestion.source == .opticalRecognition)
        let manual = try await manual(lab, title: "Handwritten", body: "no analyzer", image: image)
        #expect(manual.lines.isEmpty)
        _ = try await applied(lab, manual)
        #expect(lab.store.appliedCount == 2)
    }

    @Test func aModelFailureDoesNotWriteAndTheManualPathStillDoes() async throws {
        let lab = Lab.open()
        let image = try lab.image()
        let failed = await lab.flow.inspect(
            image,
            route: .onDeviceModel(ScriptedInterpreter { _, _ throws(InspectFailure) in
                throw .modelUnavailable(.modelNotReady)
            }),
            inspector: ScriptedImageInspector(reading: reading()),
            consent: .chosenImage
        )
        guard case .failure(.modelUnavailable(.modelNotReady)) = failed else {
            Issue.record("expected the model gate")
            return
        }
        #expect(lab.store.appliedCount == 0)
        let manual = try await manual(lab, title: "Still works", body: "typed")
        _ = try await applied(lab, manual)
        #expect(lab.store.appliedCount == 2)
    }

    @Test func systemLabelsStaySuggestionsAndDoNotRun() async throws {
        let lab = Lab.open()
        let observation = VisualSearchParticipation.observation(labels: [
            "open the archive",
            "https://example.invalid/go",
        ])
        #expect(observation.suggestion.isUncertain)
        #expect(observation.suggestion.source == .systemVisualSearch)
        #expect(observation.evidence.byteCount == 0)
        #expect(observation.evidence.staysLocal)
        #expect(observation.consent.cameraUsed == false)
        #expect(observation.consent.visualSearch == .systemQuery)
        let operation = try observation.operation()
        guard case .createItem(let draft) = operation else {
            Issue.record("expected a new item")
            return
        }
        #expect(draft.note.value.contains("https://example.invalid/go"))
        #expect(draft.note.value.contains("open the archive"))
        #expect(lab.store.appliedCount == 0)
        await VisualSearchHandoff.shared.store(observation)
        let taken = await VisualSearchHandoff.shared.take()
        #expect(taken == observation)
        #expect(await VisualSearchHandoff.shared.take() == nil)
    }
}

@Suite struct InspectFailureTests {
    @Test func emptyOversizedAndUnknownBytesAreRefused() throws {
        #expect(throws: InspectFailure.emptyImage) {
            try SelectedImage(data: Data(), origin: .userSelected)
        }
        #expect(throws: InspectFailure.imageTooLarge(bytes: InspectLimits.imageBytes + 1)) {
            try SelectedImage(data: Data(count: InspectLimits.imageBytes + 1), origin: .userSelected)
        }
        #expect(throws: InspectFailure.unsupportedImage) {
            try SelectedImage(data: Data("not an image".utf8), origin: .userSelected)
        }
    }

    @Test func cancellationAndATimeLimitWriteNothing() async throws {
        let lab = Lab.open(timeLimit: .milliseconds(40))
        let image = try lab.image()
        let hung = await lab.flow.inspect(
            image,
            route: .opticalRecognition,
            inspector: ScriptedImageInspector { _ throws(InspectFailure) in
                try await hangUntilCancelled()
                return OpticalReading(lines: [], barcodes: [], engine: .scripted)
            },
            consent: .chosenImage
        )
        guard case .failure(.timedOut) = hung else {
            Issue.record("expected the time limit, got \(hung)")
            return
        }
        #expect(lab.store.appliedCount == 0)

        let flow = PointInspectFlow(backend: lab.backend, timeLimit: .seconds(5))
        let task = Task {
            await flow.inspect(
                image,
                route: .opticalRecognition,
                inspector: ScriptedImageInspector { _ throws(InspectFailure) in
                    try await hangUntilCancelled()
                    return OpticalReading(lines: [], barcodes: [], engine: .scripted)
                },
                consent: .chosenImage
            )
        }
        task.cancel()
        let cancelled = await task.value
        guard case .failure(.cancelled) = cancelled else {
            Issue.record("expected cancellation, got \(cancelled)")
            return
        }
        #expect(lab.store.appliedCount == 0)
    }

    @Test func applyingTwiceWithOneApprovalWritesOnce() async throws {
        let lab = Lab.open()
        try await lab.seed()
        let observation = try await manual(lab, title: "Once", body: "only once")
        let review = try await reviewed(lab, observation)
        let approval = try review.approve()
        let first = try await lab.flow.apply(approval).get()
        let second = try await lab.flow.apply(approval).get()
        #expect(first.operationID == second.operationID)
        let items = try await lab.store.items(in: PointInspect.collectionID)
        #expect(items.count == 1)
    }

    @Test func anEmptyManualTitleIsNotApproved() async throws {
        let lab = Lab.open()
        let observation = try await manual(lab, title: "   ", body: "no title")
        #expect(!observation.isApprovable)
        let result = await lab.flow.review(observation)
        guard case .failure(.invalidText) = result else {
            Issue.record("expected invalid text, got \(result)")
            return
        }
        #expect(lab.store.appliedCount == 0)
    }
}

private func hangUntilCancelled() async throws(InspectFailure) {
    do {
        try await Task.sleep(for: .seconds(30))
    } catch {
        throw InspectFailure.cancelled
    }
    throw .cancelled
}

private extension InterpretationSuggestion {
    var badgeFallsBack: Bool {
        source.badge.contains("not a model")
    }
}

private func inspected(
    _ lab: Lab,
    image: SelectedImage,
    inspector: any ImageInspecting,
    consent: CaptureConsent = .chosenImage
) async throws -> Observation {
    try await lab.flow.inspect(image, route: .opticalRecognition, inspector: inspector, consent: consent).get()
}

private func manual(
    _ lab: Lab,
    title: String,
    body: String,
    image: SelectedImage? = nil
) async throws -> Observation {
    let chosen = try image ?? lab.image()
    return try await lab.flow.inspect(
        chosen,
        route: .manual(title: title, body: body),
        inspector: UnavailableImageInspector(),
        consent: .chosenImage
    ).get()
}

private func reviewed(_ lab: Lab, _ observation: Observation) async throws -> ReviewableInspection {
    try await lab.flow.review(observation).get()
}

@discardableResult
private func applied(_ lab: Lab, _ observation: Observation) async throws -> LabItem {
    _ = try await lab.flow.commit(observation).get()
    let items = try await lab.store.items(in: PointInspect.collectionID)
    let match = try #require(items.first { $0.title.value == observation.suggestion.title.trimmingCharacters(in: .whitespacesAndNewlines) })
    return match
}
