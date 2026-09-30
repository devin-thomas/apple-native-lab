import CoreVideo
import Foundation
import LabDomain
@testable import RenderThatSurvives
import Testing

/// The fixture recipes are data read with strict rules, and a hostile one starts nothing.
@Suite struct RecipeTests {
    @Test func theBundledRecipesAreTheShortAndLongFixtures() throws {
        let recipes = try RenderThatSurvives.bundledRecipes()
        #expect(recipes.map(\.id) == ["short-bars", "long-bars"])
        let short = Recipes.short
        #expect(short.segmentCount == 4 && short.jobUnits == 5 && short.outputName == "short-bars.mov")
        #expect(short.frames(ofSegment: 3) == 36..<48)
        #expect(short.shape == "2.0 s · 160×90 · 24 fps")
        let long = Recipes.long
        #expect(long.segmentCount == 8 && long.pacing == .realTime && long.durationSeconds == 24)
        // Small by design: the long fixture's generous estimate stays under 2 MB.
        #expect(long.estimatedOutputBytes < 2_000_000)
    }

    @Test func hostileRecipesAreRefused() throws {
        let expected: [(String, RecipeProblem)] = [
            ("duplicate-keys.json", .malformed),
            ("unknown-field.json", .unknownField),
            ("traversal-id.json", .invalid(.id)),
            ("oversized-frames.json", .invalid(.frameCount)),
            ("odd-width.json", .invalid(.width)),
            ("malformed.json", .malformed),
        ]
        for (name, problem) in expected {
            let data = try HostileRecipes.data(name)
            #expect(throws: problem, "\(name)") { try RenderRecipe.recipes(from: data) }
        }
        #expect(throws: RecipeProblem.malformed) { try RenderRecipe.recipes(from: Data()) }
        #expect(throws: RecipeProblem.malformed) {
            try RenderRecipe.recipes(from: Data(repeating: 0x20, count: RenderRecipe.maximumDocumentBytes + 1))
        }
    }

    @Test func aRecipeValidatesEveryField() {
        func make(width: Int = 160, frames: Int = 48, segment: Int = 12, fps: Int = 24, rate: Int = 300_000) throws(RecipeProblem) -> RenderRecipe {
            try RenderRecipe(
                id: "check", title: "Check", width: width, height: 90, framesPerSecond: fps, frameCount: frames,
                framesPerSegment: segment, pacing: .asFastAsPossible, bitRate: rate
            )
        }
        #expect(throws: RecipeProblem.invalid(.width)) { try make(width: 8) }
        #expect(throws: RecipeProblem.invalid(.framesPerSegment)) { try make(frames: 10, segment: 12) }
        #expect(throws: RecipeProblem.invalid(.framesPerSecond)) { try make(fps: 0) }
        #expect(throws: RecipeProblem.invalid(.bitRate)) { try make(rate: 10) }
        #expect((try? make(frames: 50, segment: 12))?.segmentCount == 5)
        #expect((try? make(frames: 50, segment: 12))?.frames(ofSegment: 4) == 48..<50)
    }
}

/// The frames are generated, deterministic, and the same bytes on either path.
@Suite struct FrameTests {
    static func buffer(for recipe: RenderRecipe) throws -> CVPixelBuffer {
        var buffer: CVPixelBuffer?
        let attributes: [String: Any] = [
            kCVPixelBufferIOSurfacePropertiesKey as String: [String: Any](),
            kCVPixelBufferMetalCompatibilityKey as String: true,
        ]
        let status = CVPixelBufferCreate(nil, recipe.width, recipe.height, kCVPixelFormatType_32BGRA, attributes as CFDictionary, &buffer)
        guard status == kCVReturnSuccess, let buffer else { throw PaintFailure(path: .cpu) }
        return buffer
    }

    /// SHA-256 of the CPU painter's pixels for the short recipe, row by row without padding.
    /// Changing the pattern changes these, and the fixture README's claim with them.
    static let pinned: [Int: String] = [
        0: "a01236477457e881927e284be2a66b3f039ddead9fe584ac814aaf4ee2c07df0",
        23: "0c160982af13e45b1099d4599a26259b3c1c5044279b2df230629b6ab2ac4d43",
        47: "91c9ad6b137202c9410429028f419f7d24da0d989046e8923830645ed1b8760a",
    ]

    @Test func theCPUPainterIsDeterministicAndPinned() throws {
        let pattern = FramePattern(recipe: Recipes.short)
        var digests: [Int: String] = [:]
        for frame in [0, 23, 47] {
            let first = try Self.buffer(for: Recipes.short)
            let second = try Self.buffer(for: Recipes.short)
            try CPUFramePainter().paint(pattern, frame: frame, into: first)
            try CPUFramePainter().paint(pattern, frame: frame, into: second)
            #expect(FrameCheck.digest(of: first) == FrameCheck.digest(of: second))
            #expect(FrameCheck.matches(first, pattern, frame: frame))
            digests[frame] = FrameCheck.digest(of: first)
        }
        #expect(digests == Self.pinned, "\(digests)")
        #expect(Set(digests.values).count == 3)
    }

    @Test func eachFrameShowsItsOwnSegment() {
        let pattern = FramePattern(recipe: Recipes.short)
        // The strip's cells sit at the top; the lit one is the frame's segment.
        for frame in [0, 12, 30, 47] {
            let segment = frame / Recipes.short.framesPerSegment
            let cellCenter = (segment * 160 / 4 + (segment + 1) * 160 / 4) / 2
            #expect(pattern.color(atX: cellCenter, y: 2, frame: frame) == PixelColor.lit)
        }
    }

    @Test func aWrongPixelFailsTheCheck() throws {
        let pattern = FramePattern(recipe: Recipes.short)
        let buffer = try Self.buffer(for: Recipes.short)
        try CPUFramePainter().paint(pattern, frame: 5, into: buffer)
        #expect(!FrameCheck.matches(buffer, pattern, frame: 30))
        CVPixelBufferLockBaseAddress(buffer, [])
        CVPixelBufferGetBaseAddress(buffer)!.storeBytes(of: UInt32(0xFF00_FF00), as: UInt32.self)
        CVPixelBufferUnlockBaseAddress(buffer, [])
        #expect(!FrameCheck.matches(buffer, pattern, frame: 5))
    }

    @Test(.enabled(if: GPUFramePainter.systemDefault() != nil, "needs a Metal device"))
    func theGPUPainterDrawsTheSameBytesAsTheCPUPainter() throws {
        let gpu = try #require(GPUFramePainter.systemDefault())
        for recipe in [Recipes.short, Recipes.long] {
            let pattern = FramePattern(recipe: recipe)
            for frame in [0, recipe.frameCount / 3, recipe.frameCount - 1] {
                let cpuBuffer = try Self.buffer(for: recipe)
                let gpuBuffer = try Self.buffer(for: recipe)
                try CPUFramePainter().paint(pattern, frame: frame, into: cpuBuffer)
                try gpu.paint(pattern, frame: frame, into: gpuBuffer)
                #expect(FrameCheck.digest(of: gpuBuffer) == FrameCheck.digest(of: cpuBuffer), "\(recipe.id) frame \(frame)")
            }
        }
    }
}
