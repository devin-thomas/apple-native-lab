// Draws Native Screening Room's original fixture clips (LAB-031) from code alone.
//
//   swift Fixtures/LAB-031/make_screening_clips.swift Packages/LabFeatures/Sources/ScreeningRoomPlayback/Resources/Clips
//
// Every frame, tone, and caption comes from the numbers and strings below: no camera, microphone,
// font file, or imported media is read. The drawing uses rectangles only, so no system font is
// drawn into a frame. The software H.264 encoder is used and the header timestamps are cleared,
// so two runs on the same OS and Xcode write identical bytes. Another encoder version may write
// different bytes that play the same way: the committed files and their SHA-256 in clips.json are
// the record, and the package tests check the bundled files against it.
//
// Writes three clips and clips.json:
//   screening-test-card.mov      10 s, 320x180, 15 fps H.264, a mono AAC tone that steps each
//                                second, and two subtitle tracks in one alternate group: English
//                                captions and Spanish subtitles. Neither is on by default.
//   screening-unknown-codec.mov  2 s of video only, written as H.264 and then relabeled with the
//                                sample-entry code `lab0`, which no decoder claims.
//   screening-truncated.mov      the first 2048 bytes of the test card: its movie header is missing.
import AVFoundation
import CoreMedia
import CoreVideo
import CryptoKit
import Foundation
import VideoToolbox

let arguments = CommandLine.arguments
guard arguments.count == 2 else {
    FileHandle.standardError.write(Data("usage: make_screening_clips.swift <output folder>\n".utf8))
    exit(64)
}
let output = URL(fileURLWithPath: arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

let width = 320
let height = 180
let framesPerSecond: Int32 = 15
let audioRate = 44_100.0

/// One caption: when it shows, for how long, and what it says.
struct Cue {
    let start: Double
    let end: Double
    let text: String
}

let englishCaptions = [
    Cue(start: 0.5, end: 2.5, text: "Test card, part one."),
    Cue(start: 3.0, end: 5.0, text: "[a low tone rises]"),
    Cue(start: 5.5, end: 7.5, text: "The bar keeps the time."),
    Cue(start: 8.0, end: 9.8, text: "End of the test card."),
]
let spanishSubtitles = [
    Cue(start: 0.5, end: 2.5, text: "Carta de ajuste, primera parte."),
    Cue(start: 3.0, end: 5.0, text: "Sube un tono grave."),
    Cue(start: 5.5, end: 7.5, text: "La barra marca el tiempo."),
    Cue(start: 8.0, end: 9.8, text: "Fin de la carta de ajuste."),
]

// MARK: Pictures

/// A pixel buffer drawn with rectangles: a field whose color steps each second, a progress bar,
/// and the elapsed second as a seven-segment digit.
func frame(_ index: Int, of total: Int, pool: CVPixelBufferPool) -> CVPixelBuffer {
    var buffer: CVPixelBuffer?
    CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
    guard let buffer else { fatalError("no pixel buffer") }
    CVPixelBufferLockBaseAddress(buffer, [])
    defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
    let base = CVPixelBufferGetBaseAddress(buffer)!.assumingMemoryBound(to: UInt8.self)
    let stride = CVPixelBufferGetBytesPerRow(buffer)

    func fill(_ x: Int, _ y: Int, _ w: Int, _ h: Int, _ bgra: (UInt8, UInt8, UInt8)) {
        for row in max(0, y)..<min(height, y + h) {
            for column in max(0, x)..<min(width, x + w) {
                let pixel = base + row * stride + column * 4
                pixel[0] = bgra.0; pixel[1] = bgra.1; pixel[2] = bgra.2; pixel[3] = 255
            }
        }
    }

    let second = index / Int(framesPerSecond)
    let fields: [(UInt8, UInt8, UInt8)] = [
        (96, 64, 32), (32, 96, 64), (64, 32, 96), (32, 64, 96), (96, 32, 64),
        (64, 96, 32), (80, 80, 40), (40, 80, 80), (80, 40, 80), (60, 60, 60),
    ]
    fill(0, 0, width, height, fields[second % fields.count])
    // Eight test bars along the top.
    let bars: [(UInt8, UInt8, UInt8)] = [
        (235, 235, 235), (16, 235, 235), (235, 235, 16), (16, 235, 16),
        (235, 16, 235), (16, 16, 235), (235, 16, 16), (16, 16, 16),
    ]
    for (slot, color) in bars.enumerated() { fill(slot * 40, 0, 40, 36, color) }
    // Progress along the bottom.
    let progress = (index + 1) * (width - 32) / total
    fill(16, 150, width - 32, 10, (40, 40, 40))
    fill(16, 150, progress, 10, (230, 230, 230))
    // The elapsed second as a seven-segment digit.
    let segmentsByDigit: [[Int]] = [
        [0, 1, 2, 4, 5, 6], [2, 5], [0, 2, 3, 4, 6], [0, 2, 3, 5, 6], [1, 2, 3, 5],
        [0, 1, 3, 5, 6], [0, 1, 3, 4, 5, 6], [0, 2, 5], [0, 1, 2, 3, 4, 5, 6], [0, 1, 2, 3, 5, 6],
    ]
    let (ox, oy, long, thick) = (140, 50, 40, 8)
    let white: (UInt8, UInt8, UInt8) = (245, 245, 245)
    for segment in segmentsByDigit[second % 10] {
        switch segment {
        case 0: fill(ox, oy, long, thick, white)
        case 1: fill(ox - thick, oy, thick, long, white)
        case 2: fill(ox + long, oy, thick, long, white)
        case 3: fill(ox, oy + long, long, thick, white)
        case 4: fill(ox - thick, oy + long, thick, long, white)
        case 5: fill(ox + long, oy + long, thick, long, white)
        default: fill(ox, oy + 2 * long, long, thick, white)
        }
    }
    return buffer
}

// MARK: Sound

/// A mono tone that steps up each second, with short fades so the steps do not click.
func toneSamples(seconds: Double) -> [Float] {
    let count = Int(seconds * audioRate)
    var samples = [Float](repeating: 0, count: count)
    var phase = 0.0
    let fade = Int(0.01 * audioRate)
    for index in 0..<count {
        let second = index / Int(audioRate)
        let frequency = 220.0 * pow(2.0, Double(second % 10) / 12.0)
        phase += 2 * Double.pi * frequency / audioRate
        let within = index % Int(audioRate)
        let envelope = min(1.0, Double(min(within, Int(audioRate) - within)) / Double(fade))
        samples[index] = Float(0.2 * envelope * sin(phase))
    }
    return samples
}

func audioBuffer(_ samples: ArraySlice<Float>, at start: Int, format: CMAudioFormatDescription) -> CMSampleBuffer {
    let bytes = samples.count * MemoryLayout<Float>.size
    var block: CMBlockBuffer?
    CMBlockBufferCreateWithMemoryBlock(allocator: nil, memoryBlock: nil, blockLength: bytes, blockAllocator: nil,
                                       customBlockSource: nil, offsetToData: 0, dataLength: bytes, flags: 0, blockBufferOut: &block)
    samples.withUnsafeBytes { raw in
        _ = CMBlockBufferReplaceDataBytes(with: raw.baseAddress!, blockBuffer: block!, offsetIntoDestination: 0, dataLength: bytes)
    }
    var sample: CMSampleBuffer?
    CMAudioSampleBufferCreateReadyWithPacketDescriptions(
        allocator: nil, dataBuffer: block!, formatDescription: format, sampleCount: samples.count,
        presentationTimeStamp: CMTime(value: CMTimeValue(start), timescale: CMTimeScale(audioRate)),
        packetDescriptions: nil, sampleBufferOut: &sample)
    return sample!
}

// MARK: Captions

/// A 3GPP timed-text format description, the kind a QuickTime subtitle track carries.
func textFormat() -> CMFormatDescription {
    let color: (Int, Int, Int, Int) -> [String: Int] = { red, green, blue, alpha in
        [kCMTextFormatDescriptionColor_Red as String: red, kCMTextFormatDescriptionColor_Green as String: green,
         kCMTextFormatDescriptionColor_Blue as String: blue, kCMTextFormatDescriptionColor_Alpha as String: alpha]
    }
    let extensions: [String: Any] = [
        kCMTextFormatDescriptionExtension_DisplayFlags as String: 0,
        kCMTextFormatDescriptionExtension_HorizontalJustification as String: 1,
        kCMTextFormatDescriptionExtension_VerticalJustification as String: -1,
        kCMTextFormatDescriptionExtension_BackgroundColor as String: color(0, 0, 0, 0),
        kCMTextFormatDescriptionExtension_DefaultTextBox as String: [
            kCMTextFormatDescriptionRect_Top as String: 0, kCMTextFormatDescriptionRect_Left as String: 0,
            kCMTextFormatDescriptionRect_Bottom as String: 0, kCMTextFormatDescriptionRect_Right as String: 0,
        ],
        kCMTextFormatDescriptionExtension_DefaultStyle as String: [
            kCMTextFormatDescriptionStyle_StartChar as String: 0, kCMTextFormatDescriptionStyle_EndChar as String: 0,
            kCMTextFormatDescriptionStyle_Font as String: 1, kCMTextFormatDescriptionStyle_FontFace as String: 0,
            kCMTextFormatDescriptionStyle_FontSize as String: 18,
            kCMTextFormatDescriptionStyle_ForegroundColor as String: color(255, 255, 255, 255),
        ] as [String: Any],
        // A generic family name, not a font file.
        kCMTextFormatDescriptionExtension_FontTable as String: ["1": "Sans-Serif"],
    ]
    var description: CMFormatDescription?
    let status = CMFormatDescriptionCreate(allocator: nil, mediaType: kCMMediaType_Subtitle,
                                           mediaSubType: kCMTextFormatType_3GText,
                                           extensions: extensions as CFDictionary, formatDescriptionOut: &description)
    guard status == noErr, let description else { fatalError("text format: \(status)") }
    return description
}

/// One timed-text sample: a big-endian length, then the UTF-8 text. An empty string clears the line.
func textSample(_ text: String, from start: Double, to end: Double, format: CMFormatDescription) -> CMSampleBuffer {
    let utf8 = Array(text.utf8)
    var bytes = [UInt8(utf8.count >> 8), UInt8(utf8.count & 0xFF)] + utf8
    var block: CMBlockBuffer?
    CMBlockBufferCreateWithMemoryBlock(allocator: nil, memoryBlock: nil, blockLength: bytes.count, blockAllocator: nil,
                                       customBlockSource: nil, offsetToData: 0, dataLength: bytes.count, flags: 0, blockBufferOut: &block)
    CMBlockBufferReplaceDataBytes(with: &bytes, blockBuffer: block!, offsetIntoDestination: 0, dataLength: bytes.count)
    var timing = CMSampleTimingInfo(duration: CMTime(seconds: end - start, preferredTimescale: 600),
                                    presentationTimeStamp: CMTime(seconds: start, preferredTimescale: 600),
                                    decodeTimeStamp: .invalid)
    var size = bytes.count
    var sample: CMSampleBuffer?
    CMSampleBufferCreate(allocator: nil, dataBuffer: block, dataReady: true, makeDataReadyCallback: nil, refcon: nil,
                         formatDescription: format, sampleCount: 1, sampleTimingEntryCount: 1, sampleTimingArray: &timing,
                         sampleSizeEntryCount: 1, sampleSizeArray: &size, sampleBufferOut: &sample)
    return sample!
}

/// Cues with the gaps between them filled by empty samples, so the track covers the whole clip.
func textSamples(_ cues: [Cue], through duration: Double, format: CMFormatDescription) -> [CMSampleBuffer] {
    var samples: [CMSampleBuffer] = []
    var cursor = 0.0
    for cue in cues {
        if cue.start > cursor { samples.append(textSample("", from: cursor, to: cue.start, format: format)) }
        samples.append(textSample(cue.text, from: cue.start, to: cue.end, format: format))
        cursor = cue.end
    }
    if cursor < duration { samples.append(textSample("", from: cursor, to: duration, format: format)) }
    return samples
}

// MARK: Writing

/// Feeds one writer input from a list of samples whenever it is ready, on its own queue.
final class Feeder: @unchecked Sendable {
    let input: AVAssetWriterInput
    var remaining: [() -> CMSampleBuffer?]
    let group: DispatchGroup
    let queue: DispatchQueue

    init(_ input: AVAssetWriterInput, samples: [() -> CMSampleBuffer?], group: DispatchGroup, label: String) {
        self.input = input
        self.remaining = samples.reversed()
        self.group = group
        self.queue = DispatchQueue(label: label)
    }

    func start(pixels: AVAssetWriterInputPixelBufferAdaptor? = nil, frames: [(CMTime, () -> CVPixelBuffer)] = []) {
        group.enter()
        var pending = Array(frames.reversed())
        input.requestMediaDataWhenReady(on: queue) { [self] in
            while input.isReadyForMoreMediaData {
                if let pixels {
                    guard let (time, make) = pending.popLast() else { finish(); return }
                    if !pixels.append(make(), withPresentationTime: time) { fatalError("frame append failed") }
                } else {
                    guard let next = remaining.popLast() else { finish(); return }
                    if let sample = next(), !input.append(sample) { fatalError("sample append failed") }
                }
            }
        }
    }

    private func finish() {
        input.markAsFinished()
        group.leave()
    }
}

/// A track's tagged media characteristics, as QuickTime user data. The English track is tagged as
/// captions for the deaf and hard of hearing, so players list it as SDH rather than as subtitles.
func taggedCharacteristics(_ characteristics: [AVMediaCharacteristic]) -> [AVMetadataItem] {
    characteristics.map { characteristic in
        let item = AVMutableMetadataItem()
        item.identifier = .quickTimeUserDataTaggedCharacteristic
        item.value = characteristic.rawValue as NSString
        item.dataType = kCMMetadataBaseDataType_UTF8 as String
        return item
    }
}

func write(to url: URL, seconds: Double, withSound: Bool, captions: [(String, String, [Cue], [AVMediaCharacteristic])]) throws {
    try? FileManager.default.removeItem(at: url)
    let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
    let group = DispatchGroup()

    let video = AVAssetWriterInput(mediaType: .video, outputSettings: [
        AVVideoCodecKey: AVVideoCodecType.h264,
        AVVideoWidthKey: width,
        AVVideoHeightKey: height,
        // The software encoder: the hardware one wrote a few different bytes on every run.
        AVVideoEncoderSpecificationKey: [kVTVideoEncoderSpecification_EnableHardwareAcceleratedVideoEncoder as String: false],
        AVVideoCompressionPropertiesKey: [
            AVVideoAverageBitRateKey: 90_000,
            AVVideoMaxKeyFrameIntervalKey: Int(framesPerSecond),
            AVVideoProfileLevelKey: AVVideoProfileLevelH264MainAutoLevel,
            AVVideoAllowFrameReorderingKey: false,
        ],
    ])
    video.expectsMediaDataInRealTime = false
    let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: video, sourcePixelBufferAttributes: [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        kCVPixelBufferWidthKey as String: width,
        kCVPixelBufferHeightKey as String: height,
    ])
    writer.add(video)

    var audio: AVAssetWriterInput?
    if withSound {
        let input = AVAssetWriterInput(mediaType: .audio, outputSettings: [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: audioRate,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 32_000,
        ])
        input.expectsMediaDataInRealTime = false
        writer.add(input)
        audio = input
    }

    let format = textFormat()
    var textInputs: [(AVAssetWriterInput, [CMSampleBuffer])] = []
    for (language, tag, cues, characteristics) in captions {
        let input = AVAssetWriterInput(mediaType: .subtitle, outputSettings: nil, sourceFormatHint: format)
        input.languageCode = language
        input.extendedLanguageTag = tag
        input.metadata = taggedCharacteristics(characteristics)
        input.expectsMediaDataInRealTime = false
        writer.add(input)
        textInputs.append((input, textSamples(cues, through: seconds, format: format)))
    }
    if textInputs.count > 1 {
        let alternates = AVAssetWriterInputGroup(inputs: textInputs.map(\.0), defaultInput: nil)
        guard writer.canAdd(alternates) else { fatalError("cannot group the subtitle tracks") }
        writer.add(alternates)
    }

    guard writer.startWriting() else { throw writer.error ?? CocoaError(.fileWriteUnknown) }
    writer.startSession(atSourceTime: .zero)

    let total = Int(seconds * Double(framesPerSecond))
    let pool = adaptor.pixelBufferPool!
    let frames: [(CMTime, () -> CVPixelBuffer)] = (0..<total).map { index in
        (CMTime(value: CMTimeValue(index), timescale: framesPerSecond), { frame(index, of: total, pool: pool) })
    }
    Feeder(video, samples: [], group: group, label: "video").start(pixels: adaptor, frames: frames)

    if let audio {
        let samples = toneSamples(seconds: seconds)
        var streamFormat = AudioStreamBasicDescription(
            mSampleRate: audioRate, mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked,
            mBytesPerPacket: 4, mFramesPerPacket: 1, mBytesPerFrame: 4, mChannelsPerFrame: 1, mBitsPerChannel: 32,
            mReserved: 0)
        var audioFormat: CMAudioFormatDescription?
        CMAudioFormatDescriptionCreate(allocator: nil, asbd: &streamFormat, layoutSize: 0, layout: nil,
                                       magicCookieSize: 0, magicCookie: nil, extensions: nil, formatDescriptionOut: &audioFormat)
        let chunk = 4096
        let chunks: [() -> CMSampleBuffer?] = stride(from: 0, to: samples.count, by: chunk).map { start in
            { audioBuffer(samples[start..<min(start + chunk, samples.count)], at: start, format: audioFormat!) }
        }
        Feeder(audio, samples: chunks, group: group, label: "audio").start()
    }
    for (index, (input, samples)) in textInputs.enumerated() {
        Feeder(input, samples: samples.map { sample in { sample } }, group: group, label: "text\(index)").start()
    }

    group.wait()
    writer.endSession(atSourceTime: CMTime(seconds: seconds, preferredTimescale: 600))
    let done = DispatchSemaphore(value: 0)
    writer.finishWriting { done.signal() }
    done.wait()
    guard writer.status == .completed else { throw writer.error ?? CocoaError(.fileWriteUnknown) }
    try clearTimestamps(in: url)
}

/// Zeroes the creation and modification times QuickTime writes into the movie, track, and media
/// headers, so two runs on the same system write the same header bytes. Only boxes on the path
/// moov > trak > mdia are read; each header keeps its version byte, flags, and every other field.
func clearTimestamps(in url: URL) throws {
    var data = try Data(contentsOf: url)
    func walk(_ range: Range<Int>) {
        var offset = range.lowerBound
        while offset + 8 <= range.upperBound {
            let size = data[offset..<offset + 4].reduce(0) { $0 << 8 | Int($1) }
            let type = String(decoding: data[offset + 4..<offset + 8], as: UTF8.self)
            guard size >= 8, offset + size <= range.upperBound else { return }
            switch type {
            case "moov", "trak", "mdia":
                walk(offset + 8..<offset + size)
            case "mvhd", "tkhd", "mdhd":
                let width = data[offset + 8] == 1 ? 8 : 4
                data.replaceSubrange(offset + 12..<offset + 12 + 2 * width, with: Data(count: 2 * width))
            default:
                break
            }
            offset += size
        }
    }
    walk(0..<data.count)
    try data.write(to: url)
}

func sha256(_ url: URL) throws -> String {
    SHA256.hash(data: try Data(contentsOf: url)).map { String(format: "%02x", $0) }.joined()
}

// MARK: The three clips

let testCard = output.appendingPathComponent("screening-test-card.mov")
try write(to: testCard, seconds: 10, withSound: true, captions: [
    ("eng", "en", englishCaptions, [.transcribesSpokenDialogForAccessibility, .describesMusicAndSoundForAccessibility]),
    ("spa", "es", spanishSubtitles, []),
])

// Relabel the H.264 sample entry so that no decoder claims the track. The code appears once, in
// the video track's sample description; anything else means the layout changed and the patch
// would be a guess.
let unknownCodec = output.appendingPathComponent("screening-unknown-codec.mov")
let scratch = output.appendingPathComponent("screening-unknown-codec.source.mov")
try write(to: scratch, seconds: 2, withSound: false, captions: [])
var bytes = try Data(contentsOf: scratch)
try FileManager.default.removeItem(at: scratch)
let original = Data("avc1".utf8)
var ranges: [Range<Data.Index>] = []
var searchStart = bytes.startIndex
while let found = bytes.range(of: original, in: searchStart..<bytes.endIndex) {
    ranges.append(found)
    searchStart = found.upperBound
}
guard ranges.count == 1 else { fatalError("expected one avc1 sample entry, found \(ranges.count)") }
bytes.replaceSubrange(ranges[0], with: Data("lab0".utf8))
try bytes.write(to: unknownCodec)

let truncated = output.appendingPathComponent("screening-truncated.mov")
try Data(try Data(contentsOf: testCard).prefix(2048)).write(to: truncated)

// The record the tests and the evidence read: each clip's size and SHA-256.
var manifest: [[String: Any]] = []
for url in [testCard, unknownCodec, truncated] {
    let size = try FileManager.default.attributesOfItem(atPath: url.path)[.size] as! Int
    manifest.append(["file": url.lastPathComponent, "bytes": size, "sha256": try sha256(url)])
}
let json = try JSONSerialization.data(withJSONObject: ["generator": "Fixtures/LAB-031/make_screening_clips.swift", "clips": manifest],
                                      options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
try (json + Data("\n".utf8)).write(to: output.appendingPathComponent("clips.json"))
for entry in manifest { print(entry["file"]!, entry["bytes"]!, entry["sha256"]!) }
