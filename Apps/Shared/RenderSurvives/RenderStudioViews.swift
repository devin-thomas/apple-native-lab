import AVKit
import LabCatalog
import LabDomain
import LabJobs
import RenderThatSurvives
import SwiftUI

/// Render That Survives on one page (LAB-032): choose a fixture, render it, leave, and come back
/// to the job's truth: running with its progress, stopped and resumable, or finished with the
/// published movie.
///
/// iPhone and iPad push it from the experiment's catalog page. The Mac shows the same sections in
/// its window columns (`Apps/Mac/Window/RenderColumns.swift`).
struct RenderStudioPage: View {
    @State private var model = RenderStudioModel.shared

    var body: some View {
        List {
            RenderControlsSection(model: model)
            RenderJobsSection(model: model)
            RenderOutputSection(model: model, showsPlayer: true)
            RenderReceiptsSection(model: model)
        }
        .navigationTitle(RenderThatSurvives.title)
        .task { await model.refresh() }
    }
}

/// The recipe, the two choices, and the Render button.
struct RenderControlsSection: View {
    @Bindable var model: RenderStudioModel

    var body: some View {
        Section {
            Picker("Recipe", selection: $model.selectedRecipeID) {
                ForEach(model.recipes) { recipe in
                    Text(recipe.title).tag(recipe.id)
                }
            }
            .onChange(of: model.selectedRecipeID) { Task { await model.refresh() } }
            if let recipe = model.selectedRecipe {
                SectionNote(Self.describe(recipe))
            }
            Toggle("Draw frames on the GPU when it can", isOn: $model.preferGPU)
                .accessibilityHint("When off, or when the app is in the background, the CPU draws the same frames.")
            #if os(iOS)
            Toggle("Continue in the background when iOS allows", isOn: $model.wantsBackground)
                .accessibilityHint("Asks iOS for continued processing when the render starts. Without it the render stops at a checkpoint when you leave.")
            #endif
            Button {
                Task { await model.start() }
            } label: {
                Label("Render", systemImage: "play.rectangle.fill")
                    #if os(iOS)
                    .frame(maxWidth: .infinity)
                    #endif
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .buttonBorderShape(.roundedRectangle(radius: 12))
            .disabled(!model.canStart)
            .keyboardShortcut(.return, modifiers: .command)
            .accessibilityHint("Checks space, records a job, and renders the chosen recipe.")
            if let message = model.lastMessage {
                Text(message)
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if case .unavailable(let reason) = model.phase {
                Label(reason, systemImage: "exclamationmark.triangle")
                    .font(.callout)
                    .foregroundStyle(.orange)
            }
        } header: {
            Text("Render")
        }
    }

    static func describe(_ recipe: RenderRecipe) -> String {
        let pacing = recipe.pacing == .realTime
            ? "Paced at playback speed, so it takes about \(Int(recipe.durationSeconds)) seconds: time to leave and come back."
            : "Renders as fast as the device can."
        let space = ByteCountFormatter.string(fromByteCount: recipe.requiredBytes, countStyle: .file)
        return "\(recipe.shape), \(recipe.segmentCount) segments, each saved as a checkpoint. \(pacing) Needs up to \(space) free, checked before it starts. Generated frames; no media is read."
    }
}

/// Unfinished jobs with their controls, then finished ones.
struct RenderJobsSection: View {
    let model: RenderStudioModel

    var body: some View {
        Section {
            if model.jobs.isEmpty {
                Text("No render jobs yet. A job you start stays here, with its state, even after the app quits.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(model.activeJobs) { job in
                RenderJobCard(model: model, job: job)
            }
            ForEach(model.finishedJobs.prefix(8)) { job in
                RenderJobRow(job: job)
            }
        } header: {
            Text("Jobs")
        }
    }
}

/// A running or stopped job: its state, progress, where it may run, and its actions.
struct RenderJobCard: View {
    let model: RenderStudioModel
    let job: LabJob

    var body: some View {
        let live = model.isLive(job)
        let progress = model.progress[job.id]
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(job.title.value)
                    .font(.headline)
                Spacer()
                StatusBadge(status: RenderJobRow.status(of: job, live: live))
            }
            if let progress, live {
                ProgressView(value: progress.fraction) {
                    Text(Self.step(progress))
                        .font(.callout)
                }
                .accessibilityValue("\(Int(progress.fraction * 100)) percent")
                Text(progress.runway.summary)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else if let fraction = job.progress.fraction {
                ProgressView(value: fraction) {
                    Text("\(job.progress.phrase) steps saved")
                        .font(.callout)
                }
            }
            Text(Self.explanation(job, live: live))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                if live {
                    Button("Pause", systemImage: "pause.fill") { Task { await model.pause(job) } }
                        .accessibilityHint("Stops at the next frame and keeps finished segments.")
                } else if case .interrupted = job.phase {
                    Button("Resume", systemImage: "play.fill") { Task { await model.resume(job) } }
                        .buttonStyle(.borderedProminent)
                        .disabled(model.isWorking)
                        .accessibilityHint("Continues from the last saved checkpoint.")
                }
                Button("Cancel", systemImage: "xmark", role: .destructive) { Task { await model.cancel(job) } }
                    .keyboardShortcut(live ? .cancelAction : nil)
                    .accessibilityHint("Discards this job's work. A movie published earlier is kept.")
            }
            .buttonStyle(.bordered)
        }
        .padding(.vertical, 4)
    }

    static func step(_ progress: RenderProgress) -> String {
        let path = progress.lastPath.map { $0 == .gpu ? " · drawn on the GPU" : " · drawn on the CPU" } ?? ""
        return switch progress.step {
        case .repairing(let segment): "Re-encoding missing segment \(segment + 1)\(path)"
        case .rendering(let segment): "Segment \(segment + 1) · frame \(progress.framesDone)\(path)"
        case .assembling: "Joining segments and checking the movie"
        case .publishing: "Publishing"
        }
    }

    static func explanation(_ job: LabJob, live: Bool) -> String {
        switch job.phase {
        case .running where live:
            "Each finished segment is saved as a checkpoint before the next begins."
        case .running:
            "Recorded as running, but no worker runs it in this app. It will read as stopped once recovery runs."
        case .interrupted(let reason):
            "Stopped because \(reason.clause). \(job.progress.phrase) steps are saved; Resume continues from there."
        case .succeeded, .failed, .cancelled:
            ""
        }
    }
}

/// A finished job in one line.
struct RenderJobRow: View {
    let job: LabJob

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(job.title.value)
                Spacer()
                StatusBadge(status: Self.status(of: job, live: false))
            }
            switch job.phase {
            case .succeeded(let output):
                Text("\(output.name) · \(ByteCountFormatter.string(fromByteCount: output.byteCount, countStyle: .file)) · \(output.summary)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            case .failed(let failure):
                Text(failure.message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            default:
                EmptyView()
            }
        }
        .accessibilityElement(children: .combine)
    }

    static func status(of job: LabJob, live: Bool) -> StatusDescriptor {
        switch job.phase {
        case .running: StatusDescriptor(kind: "Job", title: live ? "Running" : "Not running", symbol: live ? "gearshape.2" : "questionmark.circle", tone: .active)
        case .interrupted: StatusDescriptor(kind: "Job", title: "Stopped, can resume", symbol: "pause.circle", tone: .attention)
        case .succeeded: StatusDescriptor(kind: "Job", title: "Finished", symbol: "checkmark.circle", tone: .success)
        case .failed: StatusDescriptor(kind: "Job", title: "Failed", symbol: "xmark.octagon", tone: .critical)
        case .cancelled: StatusDescriptor(kind: "Job", title: "Cancelled", symbol: "xmark.circle", tone: .neutral)
        }
    }
}

/// The selected recipe's published movie, read from the file, with the job that recorded it.
struct RenderOutputSection: View {
    let model: RenderStudioModel
    let showsPlayer: Bool

    var body: some View {
        Section {
            if let output = model.output {
                LabeledContent("File", value: output.name)
                LabeledContent("Size", value: ByteCountFormatter.string(fromByteCount: output.byteCount, countStyle: .file))
                LabeledContent("SHA-256") {
                    Text(output.sha256.prefix(16) + "…")
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                        .accessibilityLabel("Starts \(output.sha256.prefix(8).map(String.init).joined(separator: " "))")
                }
                if let job = output.job, case .succeeded(let recorded) = job.phase {
                    SectionNote("Matches the digest that job “\(job.title)” recorded. \(recorded.summary).")
                } else {
                    SectionNote("No finished job in the store records this file's digest.")
                }
                if showsPlayer {
                    RenderPlayer(output: output)
                }
            } else {
                Text("Nothing published yet for this recipe. A movie appears here only after every segment is saved, joined, and checked.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } header: {
            Text("Published")
        }
    }
}

/// Plays the published movie. It reloads when the file's digest changes.
struct RenderPlayer: View {
    let output: RenderStudioModel.Output

    var body: some View {
        VideoPlayer(player: AVPlayer(url: output.url))
            .aspectRatio(16 / 9, contentMode: .fit)
            .frame(maxWidth: 480)
            .id(output.sha256)
            .accessibilityLabel("Published movie \(output.name)")
    }
}

/// This session's render receipts, newest first.
struct RenderReceiptsSection: View {
    let model: RenderStudioModel
    /// The Mac opens a receipt in the window's inspector; iPhone pushes it.
    var inspect: ((ReceiptRecord) -> Void)?

    var body: some View {
        Section {
            let receipts = model.receipts
            if receipts.isEmpty {
                Text("No job steps yet in this session. Each start, checkpoint, stop, and finish leaves a receipt.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(receipts.prefix(8)) { record in
                if let inspect {
                    Button { inspect(record) } label: { ReceiptRow(record: record) }
                        .buttonStyle(.plain)
                        .accessibilityHint("Shows the receipt in the inspector.")
                } else {
                    NavigationLink {
                        ReceiptDetailView(record: record)
                            .navigationTitle("Receipt")
                            #if os(iOS)
                            .navigationBarTitleDisplayMode(.inline)
                            #endif
                    } label: {
                        ReceiptRow(record: record)
                    }
                }
            }
        } header: {
            Text("Receipts")
        }
    }
}

/// The experiment page's entry: the Mac shows the experiment in this window, iPhone pushes it.
struct RenderLaunch: View {
    let experiment: RegisteredExperiment
    #if os(macOS)
    @Environment(MainWindowState.self) private var window: MainWindowState?
    #endif

    var body: some View {
        if experiment.id == RenderThatSurvives.experimentID {
            #if os(macOS)
            Button {
                window?.destination = .renderSurvives
            } label: {
                Label("Open \(RenderThatSurvives.title)", systemImage: RenderThatSurvives.symbol)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .buttonBorderShape(.roundedRectangle(radius: 8))
            .disabled(window == nil)
            .help("Show the experiment in this window (⌘9)")
            .accessibilityHint("Shows the experiment in this window.")
            #else
            NavigationLink {
                RenderStudioPage()
                    .navigationBarTitleDisplayMode(.inline)
            } label: {
                Label("Open \(RenderThatSurvives.title)", systemImage: RenderThatSurvives.symbol)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .buttonBorderShape(.roundedRectangle(radius: 12))
            .accessibilityHint("Opens the experiment.")
            #endif
        }
    }
}
