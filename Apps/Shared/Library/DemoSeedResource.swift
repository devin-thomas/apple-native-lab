import Foundation
import LabStore

/// The demo seed bundled with the host (`Fixtures/demo/seed.json` in the repository).
///
/// It is data, validated whole by `DemoFixture` before anything reaches the store, so a damaged
/// file produces an error and writes nothing.
enum DemoSeedResource {
    enum LoadError: Error, Hashable {
        case missing
        case rejected(DemoFixtureError)
    }

    static func load(from bundle: Bundle = .main) throws(LoadError) -> DemoFixture {
        guard let url = bundle.url(forResource: "seed", withExtension: "json") else { throw .missing }
        do {
            return try DemoFixture(contentsOf: url)
        } catch {
            throw .rejected(error)
        }
    }
}
