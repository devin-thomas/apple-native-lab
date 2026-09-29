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

    /// Provenance measured outside a bundle, such as by a package test run or CI. Blank values
    /// become "unknown" rather than being invented.
    public init(
        sourceRevision: String,
        sdkName: String,
        xcodeVersion: String,
        xcodeBuild: String = "unknown",
        appVersion: String = "unknown",
        buildNumber: String = "unknown",
        buildProfile: String = "unknown",
        minimumOS: String = "unknown"
    ) {
        func known(_ raw: String) -> String { raw.isBlank ? "unknown" : raw }
        self.sourceRevision = known(sourceRevision)
        self.sdkName = known(sdkName)
        self.xcodeVersion = known(xcodeVersion)
        self.xcodeBuild = known(xcodeBuild)
        self.appVersion = known(appVersion)
        self.buildNumber = known(buildNumber)
        self.buildProfile = known(buildProfile)
        self.minimumOS = known(minimumOS)
    }

    public static var current: BuildProvenance {
        BuildProvenance(infoDictionary: Bundle.main.infoDictionary ?? [:])
    }

    /// The toolchain in one line, such as "Xcode 27.0 (27A266a), macosx27.0".
    public var toolchainSummary: String {
        "Xcode \(xcodeVersion) (\(xcodeBuild)), \(sdkName)"
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

/// Evidence records carry provenance as JSON. A missing or blank value decodes as "unknown".
extension BuildProvenance: Codable {
    private enum CodingKeys: String, CodingKey {
        case sourceRevision
        case sdkName
        case xcodeVersion
        case xcodeBuild
        case appVersion
        case buildNumber
        case buildProfile
        case minimumOS
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        func value(_ key: CodingKeys) throws -> String {
            try container.decodeIfPresent(String.self, forKey: key) ?? "unknown"
        }
        self.init(
            sourceRevision: try value(.sourceRevision),
            sdkName: try value(.sdkName),
            xcodeVersion: try value(.xcodeVersion),
            xcodeBuild: try value(.xcodeBuild),
            appVersion: try value(.appVersion),
            buildNumber: try value(.buildNumber),
            buildProfile: try value(.buildProfile),
            minimumOS: try value(.minimumOS)
        )
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(sourceRevision, forKey: .sourceRevision)
        try container.encode(sdkName, forKey: .sdkName)
        try container.encode(xcodeVersion, forKey: .xcodeVersion)
        try container.encode(xcodeBuild, forKey: .xcodeBuild)
        try container.encode(appVersion, forKey: .appVersion)
        try container.encode(buildNumber, forKey: .buildNumber)
        try container.encode(buildProfile, forKey: .buildProfile)
        try container.encode(minimumOS, forKey: .minimumOS)
    }
}
