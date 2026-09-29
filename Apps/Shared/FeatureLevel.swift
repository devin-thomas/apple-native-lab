/// Which generation of platform adapters this binary was compiled with (ADR-009).
///
/// `LAB_SDK_27` is set by Config/Base.xcconfig only when building against a 27 SDK, so an
/// older Xcode still builds the 26-family core with the newer adapters compiled out.
enum FeatureLevel: String {
    case sdk27 = "27 SDK: newer adapters available"
    case compatibility = "26-family compatibility: newer adapters compiled out"

    static var current: FeatureLevel {
        #if LAB_SDK_27
        .sdk27
        #else
        .compatibility
        #endif
    }
}
