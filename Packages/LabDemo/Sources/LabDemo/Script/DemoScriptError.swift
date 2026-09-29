import LabDomain
import LabStore

/// Why a demo script was rejected. Nothing runs for a rejected script.
///
/// Paths name fields and positions, such as `steps[3].updateItem.expected`, never values.
public enum DemoScriptError: Error, Hashable, Sendable {
    /// The script file could not be read safely from its folder.
    case scriptFile(ConfinementError)
    /// The script file is not strict JSON: duplicate keys, bad UTF-8, too deep, or bad syntax.
    case invalidJSON(StrictJSONError)
    case unsupportedFormat
    case unsupportedFormatVersion(Int)
    /// A field is missing or has the wrong type.
    case malformed(path: String)
    /// A field this format does not define. Rejected rather than ignored.
    case unknownField(path: String)
    /// A field has the right type but an invalid value, such as a blank title or revision 0.
    case invalidValue(path: String)
    /// The seed file could not be read safely from the script's folder.
    case seedFile(ConfinementError)
    case invalidSeedJSON(StrictJSONError)
    case seed(DemoFixtureError)
    /// The subject is not a ticket or experiment ID such as CORE-009 or LAB-001-B.
    case invalidSubject
    case blankField(String)
    case noSteps
    case tooManySteps(limit: Int)
    case duplicateStep(DemoStepID)
    /// Two `perform` steps share a request ID, so the second would replay the first.
    case duplicateRequest(DemoStepID)
    /// A step states a Reset Demo operation with its own seed. Scripts reset with their seed only.
    case resetDemoNeedsScriptSeed(DemoStepID)
    /// The first `perform` step is not Reset Demo, so the run would not start from the seed.
    case firstChangeMustResetDemo
    /// An approval names no step, or a step that is not a later `perform` step.
    case invalidApproval(DemoStepID)
    /// An undo names no step, or a step that is not an earlier `perform` step.
    case invalidUndo(DemoStepID)
}
