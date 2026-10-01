/// LAB-045 Ink Has Structure: annotate sample media and keep the ink as editable, anchored data.
///
/// The module owns the document model, the working store, save planning, and the flattened-preview
/// export. Hosts draw with mouse/touch (and PencilKit on iPhone when available), type notes, and
/// commit saves through `OperationService` as the app UI.
public enum InkHasStructure {
    public static let experimentID = "LAB-045"
    public static let title = "Ink Has Structure"
    public static let symbol = "pencil.and.outline"
    public static let fallback = "Mouse/touch annotations and typed notes."
}
