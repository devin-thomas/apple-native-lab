import Foundation

/// What produced the running binary, read from the bundle's Info.plist.
///
/// `DTSDKName`, `DTXcode`, and `DTXcodeBuild` are written by Xcode at build time, so they
/// describe the real toolchain rather than a documented intention.
public struct BuildProvenance: Sendable, Equatable {
    public var appVersion: String
    public var buildNumber: String
    public var sourceRevision: String
    public var buildProfile: String
    public var sdkName: String
    public var xcodeVersion: String
    public var xcodeBuild: String
    public var minimumOS: String

    public init(infoDictionary info: [String: Any]) {
        func value(_ key: String) -> String {
            guard let raw = info[key] as? String, !raw.isEmpty else { return "unknown" }
            return raw
        }
        appVersion = value("CFBundleShortVersionString")
        buildNumber = value("CFBundleVersion")
        sourceRevision = value("LabSourceRevision")
        buildProfile = value("LabBuildProfile")
        sdkName = value("DTSDKName")
        xcodeVersion = Self.readableXcodeVersion(value("DTXcode"))
        xcodeBuild = value("DTXcodeBuild")
        let minimum = value("MinimumOSVersion")
        minimumOS = minimum == "unknown" ? value("LSMinimumSystemVersion") : minimum
    }

    public static var current: BuildProvenance {
        BuildProvenance(infoDictionary: Bundle.main.infoDictionary ?? [:])
    }

    /// Xcode records its version as digits, such as "2700" for 27.0 or "2631" for 26.3.1.
    static func readableXcodeVersion(_ raw: String) -> String {
        guard raw.count == 4, raw.allSatisfy(\.isNumber) else { return raw }
        let digits = Array(raw)
        let major = Int(String(digits[0...1])) ?? 0
        let minor = String(digits[2])
        let patch = String(digits[3])
        return patch == "0" ? "\(major).\(minor)" : "\(major).\(minor).\(patch)"
    }
}
