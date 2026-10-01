import SwiftUI

/// The content column for Local Model Bench (LAB-015): the four runs and the corpus.
struct LocalModelBenchListColumn: View {
    @Bindable var window: MainWindowState

    var body: some View {
        LocalModelBenchPage(session: window.bench, searchText: window.searchText)
    }
}

/// The detail column: the selected run's export, one phase and one thermal class.
struct LocalModelBenchDetailColumn: View {
    @Bindable var window: MainWindowState

    var body: some View {
        LocalModelBenchExport(report: window.bench.selection.flatMap { window.bench.reports[$0] })
    }
}
