@testable import InkHasStructure
import Foundation
import Testing

@Suite struct AnchorTests {
    @Test func anchorsStayInsideUnitSpace() throws {
        let anchor = try AnnotationAnchor(x: 0.25, y: 0.75)
        #expect(anchor.x == 0.25)
        #expect(anchor.y == 0.75)
        #expect(throws: InkError.self) { try AnnotationAnchor(x: -0.1, y: 0.5) }
        #expect(throws: InkError.self) { try AnnotationAnchor(x: 0.5, y: 1.1) }
        #expect(throws: InkError.self) { try AnnotationAnchor(x: .nan, y: 0.5) }
    }

    @Test func pointConversionRoundTripsThroughDocumentSize() throws {
        let size = try DocumentSize(width: 320, height: 240)
        let anchor = try AnnotationAnchor.from(pointX: 160, pointY: 120, documentWidth: 320, documentHeight: 240)
        let point = anchor.point(in: size)
        #expect(point.x == 160)
        #expect(point.y == 120)
    }

    @Test func resizeKeepsRelativePlacement() throws {
        let small = try DocumentSize(width: 160, height: 120)
        let large = try DocumentSize(width: 320, height: 240)
        let anchor = try AnnotationAnchor(x: 0.5, y: 0.25)
        let before = anchor.point(in: small)
        let after = anchor.point(in: large)
        #expect(before.x == 80)
        #expect(before.y == 30)
        #expect(after.x == 160)
        #expect(after.y == 60)
        #expect(after.x / large.width == before.x / small.width)
        #expect(after.y / large.height == before.y / small.height)
    }
}
