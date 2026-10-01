import Foundation
import LabDomain
import Testing
@testable import CommerceWithoutTricks

@Suite struct CommerceConfigurationTests {
    @Test func localStoreKitProductsMatchTheSimulatorFixtures() throws {
        var root = URL(filePath: #filePath)
        for _ in 0..<5 { root.deleteLastPathComponent() }
        let data = try Data(contentsOf: root.appending(path: "Fixtures/LAB-040/Commerce.storekit"))
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let products = try #require(json["products"] as? [[String: Any]])
        #expect(Set(products.compactMap { $0["productID"] as? String }) == Set(CommerceFixture.products.map { $0.id.rawValue }))
        for fixture in CommerceFixture.products {
            let product = try #require(products.first { $0["productID"] as? String == fixture.id.rawValue })
            #expect(product["displayPrice"] as? String == "0.00")
            #expect(product["type"] as? String == "NonConsumable")
            let localization = try #require((product["localizations"] as? [[String: String]])?.first)
            #expect(localization["displayName"] == fixture.displayName)
            #expect(localization["description"]?.contains("No real charge") == true)
        }
    }
}
