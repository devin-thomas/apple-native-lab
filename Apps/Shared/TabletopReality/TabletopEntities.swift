import Foundation
import LabDomain
import RealityKit
import TabletopReality
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Builds the scene's RealityKit entities from the kit, and keeps them in step with the anchors.
///
/// One controller serves one view: the virtual table's `RealityView`, or the live AR view, where
/// the same content hangs off the table's origin anchor instead of a drawn table. Every object is
/// procedural primitives in the kit's palette; nothing is loaded from a file or the network.
@MainActor
final class TabletopSceneController {
    static let tableName = LabAnchorNames.prefix + "table"
    static let objectPrefix = LabAnchorNames.prefix + "object."

    /// The table's frame: origin at the center of its top, x right, y up, z toward the viewer.
    let root = Entity()
    private var objects: [AnchorID: (fixture: FixtureKey, entity: Entity)] = [:]
    private var built = false

    /// Builds the table once. In AR, `drawsTable` is false: the real table is there, so only a
    /// thin outline of the kit's table marks where objects may go.
    func build(kit: TabletopKit, drawsTable: Bool) {
        guard !built else { return }
        built = true
        root.name = LabAnchorNames.prefix + "table-root"
        let table = kit.table
        let width = Self.meters(table.width)
        let depth = Self.meters(table.depth)
        if drawsTable {
            let thickness = Self.meters(table.thickness)
            let slab = ModelEntity(
                mesh: .generateBox(width: width, height: thickness, depth: depth, cornerRadius: 0.01),
                materials: [Self.material(table.color)]
            )
            slab.name = Self.tableName
            slab.position = [0, -thickness / 2, 0]
            slab.components.set(CollisionComponent(shapes: [.generateBox(width: width, height: thickness, depth: depth)]))
            slab.components.set(InputTargetComponent())
            root.addChild(slab)
            // Legs, so the table reads as a table from any angle.
            let legHeight: Float = 0.42
            for x in [-1, 1] as [Float] {
                for z in [-1, 1] as [Float] {
                    let leg = ModelEntity(mesh: .generateCylinder(height: legHeight, radius: 0.02), materials: [Self.material(.bark)])
                    leg.position = [x * (width / 2 - 0.06), -thickness - legHeight / 2, z * (depth / 2 - 0.06)]
                    root.addChild(leg)
                }
            }
        } else {
            var outline = UnlitMaterial(color: Self.color(.sail))
            outline.blending = .transparent(opacity: 0.25)
            let mat = ModelEntity(mesh: .generatePlane(width: width, depth: depth, cornerRadius: 0.02), materials: [outline])
            mat.name = Self.tableName
            mat.position = [0, 0.001, 0]
            mat.components.set(CollisionComponent(shapes: [.generateBox(width: width, height: 0.002, depth: depth)]))
            mat.components.set(InputTargetComponent())
            root.addChild(mat)
        }
        // The front edge, where "toward you" points.
        let edge = ModelEntity(mesh: .generateBox(width: width * 0.9, height: 0.002, depth: 0.01), materials: [UnlitMaterial(color: Self.color(.sail))])
        edge.position = [0, 0.001, depth / 2 - 0.015]
        root.addChild(edge)

        let light = DirectionalLight()
        light.light.intensity = 2_500
        light.shadow = DirectionalLightComponent.Shadow(maximumDistance: 2, depthBias: 1)
        light.look(at: .zero, from: [0.4, 1.2, 0.8], relativeTo: root)
        root.addChild(light)
    }

    /// Adds, moves, and removes object entities so they match `anchors`, and marks the selection.
    func sync(kit: TabletopKit, anchors: [LabAnchor], selection: AnchorID?) {
        let current = Set(anchors.map(\.id))
        for (id, object) in objects where !current.contains(id) {
            object.entity.removeFromParent()
            objects[id] = nil
        }
        for anchor in anchors {
            let entity: Entity
            if let existing = objects[anchor.id], existing.fixture == anchor.fixture {
                entity = existing.entity
            } else {
                objects[anchor.id]?.entity.removeFromParent()
                entity = Self.object(for: anchor, in: kit)
                root.addChild(entity)
                objects[anchor.id] = (anchor.fixture, entity)
            }
            entity.transform = Self.transform(of: anchor.pose)
            entity.findEntity(named: "selection")?.isEnabled = anchor.id == selection
        }
    }

    /// The anchor an entity belongs to, walking up from a tapped part.
    static func anchorID(of entity: Entity) -> AnchorID? {
        var node: Entity? = entity
        while let current = node {
            if current.name.hasPrefix(objectPrefix), let uuid = UUID(uuidString: String(current.name.dropFirst(objectPrefix.count))) {
                return AnchorID(rawValue: uuid)
            }
            node = current.parent
        }
        return nil
    }

    static func isTable(_ entity: Entity) -> Bool { entity.name == tableName }

    /// A point in the scene's space as whole millimeters on the table: `(x, z)`.
    func tablePoint(fromScene position: SIMD3<Float>) -> (x: Int, z: Int) {
        let local = root.convert(position: position, from: nil)
        return (Int((local.x * 1_000).rounded()), Int((local.z * 1_000).rounded()))
    }

    // MARK: Building

    static func object(for anchor: LabAnchor, in kit: TabletopKit) -> Entity {
        let entity = Entity()
        entity.name = objectPrefix + anchor.id.rawValue.uuidString
        let radius: Float
        let height: Float
        if let fixture = kit.fixture(anchor.fixture) {
            radius = meters(fixture.radius)
            height = meters(fixture.height)
            for part in fixture.parts { entity.addChild(model(for: part)) }
        } else {
            // A fixture this kit does not draw still occupies its place, as a plain marker.
            radius = 0.1
            height = 0.05
            let marker = ModelEntity(mesh: .generateBox(size: [0.12, height, 0.12], cornerRadius: 0.01), materials: [material(.metal)])
            marker.position = [0, height / 2, 0]
            entity.addChild(marker)
        }
        entity.components.set(CollisionComponent(shapes: [
            ShapeResource.generateBox(width: radius * 2, height: height, depth: radius * 2).offsetBy(translation: [0, height / 2, 0]),
        ]))
        entity.components.set(InputTargetComponent())

        let ring = ModelEntity(mesh: .generateCylinder(height: 0.002, radius: radius + 0.012), materials: [UnlitMaterial(color: .systemYellow)])
        ring.name = "selection"
        ring.position = [0, 0.001, 0]
        ring.isEnabled = false
        entity.addChild(ring)
        return entity
    }

    static func model(for part: KitPart) -> ModelEntity {
        let size = SIMD3<Float>(meters(part.size.x), meters(part.size.y), meters(part.size.z))
        let mesh: MeshResource = switch part.shape {
        case .box: .generateBox(size: size, cornerRadius: min(size.x, size.y, size.z) * 0.08)
        case .cylinder: .generateCylinder(height: size.y, radius: size.x / 2)
        case .cone: .generateCone(height: size.y, radius: size.x / 2)
        case .sphere: .generateSphere(radius: size.x / 2)
        }
        let model = ModelEntity(mesh: mesh, materials: [material(part.color)])
        model.position = [meters(part.offset.x), meters(part.offset.y), meters(part.offset.z)]
        return model
    }

    static func transform(of pose: AnchorPose) -> Transform {
        Transform(
            rotation: simd_quatf(angle: Float(pose.yaw) * .pi / 180, axis: [0, 1, 0]),
            translation: [meters(pose.x), meters(pose.y), meters(pose.z)]
        )
    }

    static func meters(_ millimeters: Int) -> Float { Float(millimeters) / 1_000 }

    static func material(_ color: KitColor) -> any RealityKit.Material {
        if color.isEmissive { return UnlitMaterial(color: Self.color(color)) }
        return SimpleMaterial(color: Self.color(color), roughness: color == .glass ? 0.1 : 0.7, isMetallic: color == .metal)
    }

    #if os(macOS)
    static func color(_ color: KitColor) -> NSColor {
        let c = color.components
        return NSColor(srgbRed: c.red, green: c.green, blue: c.blue, alpha: 1)
    }
    #else
    static func color(_ color: KitColor) -> UIColor {
        let c = color.components
        return UIColor(red: c.red, green: c.green, blue: c.blue, alpha: 1)
    }
    #endif
}
