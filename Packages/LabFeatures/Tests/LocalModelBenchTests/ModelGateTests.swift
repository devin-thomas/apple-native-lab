import Testing
@testable import LocalModelBench

/// The license and the memory budget are checked before a loader runs.
@Suite struct ModelGateTests {
    @Test func aModelLargerThanTheBudgetIsRefusedBeforeTheLoader() async throws {
        let spy = LoadSpy()
        let huge = try ModelDescriptor(id: "oversized", license: .fixture, declaredMemoryBytes: 4_000_000_000)
        let executor = FixtureExecutor { await spy.load($0) }
        await #expect(throws: BenchError.exceedsMemory(required: 4_000_000_000, available: 1_000)) {
            try await executor.run(
                phase: .measured, thermal: .cold, model: huge, availableBytes: 1_000, machine: BenchFixtures.machine
            )
        }
        #expect(await spy.calls == 0)
    }

    @Test func anUnreviewedLicenseIsRefusedBeforeTheLoader() async throws {
        let spy = LoadSpy()
        let model = try ModelDescriptor(id: "foreign", license: .unreviewed("other"), declaredMemoryBytes: 1_024)
        let executor = FixtureExecutor { await spy.load($0) }
        await #expect(throws: BenchError.licenseRefused) {
            try await executor.run(
                phase: .measured, thermal: .cold, model: model, availableBytes: BenchFixtures.roomy, machine: BenchFixtures.machine
            )
        }
        #expect(await spy.calls == 0)
    }

    @Test func aMissingBudgetIsRefusedAtTheDescriptor() throws {
        #expect(throws: BenchError.missingMemoryBudget) {
            try ModelDescriptor(id: "blank", license: .fixture, declaredMemoryBytes: 0)
        }
    }

    @Test func aBlankUnreviewedLicenseIsRefusedAtTheDescriptor() {
        #expect(throws: BenchError.licenseRefused) {
            try ModelDescriptor(id: "blank", license: .unreviewed("  "), declaredMemoryBytes: 1_024)
        }
    }

    @Test func theFixtureModelIsAdmittedAndAllocatesNothing() async throws {
        let spy = LoadSpy()
        let report = try await BenchFixtures.measured(.cold, spy: spy)
        #expect(await spy.calls == 1)
        #expect(report.allocatedBytes == 0)
        #expect(report.inference == false)
        #expect(report.declaredMemoryBytes == ModelDescriptor.fixture.declaredMemoryBytes)
        #expect(report.declaredMemoryBytes <= report.availableBytes)
    }
}
