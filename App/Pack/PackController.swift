import AppKit
import SwiftUI

/// Runs one pack at a time and tells the activity capsule how it's going.
@Observable
final class PackController {
    struct Activity: Equatable {
        typealias Phase = ActivityPhase
        /// "Project.zip"
        let name: String
        var phase: Phase
        /// What packing put on disk, for Show in Finder.
        var placed: [URL] = []
        var verified = false
        /// Sample runs have nothing to stop or show.
        var isSample = false

        var doneTitle: String {
            let file = placed.first?.lastPathComponent ?? name
            let parts = placed.count > 1 ? String(localized: " in \(placed.count) parts") : ""
            return String(localized: "Packed “\(file)”\(parts)")
        }
    }

    struct Job: Sendable {
        var items: [TreeStream.Item]
        var totalBytes: Int64
        var attributes: Bool
        var request: CreateRequest
        /// The archive's name without extension.
        var name: String
        var destination: URL
        var conflict: ArchiveCreation.Conflict = .keepBoth
        var cleanupDirectory: URL?
    }

    private(set) var activity: Activity?
    private var task: Task<Void, Never>?
    /// The last real pack, for a failure's Try Again / Choose Another Folder.
    private var lastJob: Job?

    var isRunning: Bool {
        if case .running = activity?.phase { true } else { false }
    }

    func start(_ job: Job) {
        task?.cancel()
        lastJob = job
        let fileName = job.name + "." + job.request.format.fileExtension
        activity = Activity(name: fileName, phase: .running(0))
        task = Task { [weak self] in
            defer { if let directory = job.cleanupDirectory { try? FileManager.default.removeItem(at: directory) } }
            do {
                let result = try await ArchiveCreation.run(
                    job.items, totalBytes: job.totalBytes, attributes: job.attributes, request: job.request,
                    named: job.name, in: job.destination, conflict: job.conflict
                ) { fraction in
                    Task { @MainActor in self?.advance(to: fraction) }
                }
                guard let self else { return }
                activity?.placed = result.placed
                activity?.verified = result.report.verified
                withAnimation(Motion.current(Motion.status)) { activity?.phase = .done }
            } catch {
                let failure = Failure(error, .pack, name: fileName, destination: job.destination, needs: job.totalBytes)
                let cancelled = EngineError(error).failure == .cancelled
                withAnimation(Motion.current(cancelled ? Motion.exit : Motion.status)) {
                    if cancelled {
                        self?.activity = nil
                    } else {
                        self?.activity?.phase = .failed(failure)
                    }
                }
                return
            }
            await self?.fadeOut(after: .seconds(6))
        }
    }

    /// A stand-in run for sample files, so the capsule's states can be designed and reviewed.
    func simulate(name: String) {
        task?.cancel()
        activity = Activity(name: name, phase: .running(0), isSample: true)
        task = Task { [weak self] in
            for tick in 1...24 {
                try? await Task.sleep(for: .milliseconds(60))
                guard !Task.isCancelled else { return }
                withAnimation(Motion.current(.linear(duration: 0.06))) { self?.activity?.phase = .running(Double(tick) / 24) }
            }
            withAnimation(Motion.current(Motion.status)) { self?.activity?.phase = .done }
            await self?.fadeOut(after: .seconds(3))
        }
    }

    func cancel() {
        task?.cancel()
    }

    /// A fixed state for design review.
    func preview(name: String, phase: Activity.Phase, verified: Bool = false) {
        task?.cancel()
        activity = Activity(name: name, phase: phase, verified: verified, isSample: true)
    }

    func dismiss() {
        task?.cancel()
        withAnimation(Motion.current(Motion.exit)) { activity = nil }
    }

    /// A failed pack's one next step: the same pack again, here or in a folder people choose.
    func follow(_ action: Failure.Action) {
        guard let job = lastJob else { return dismiss() }
        switch action {
        case .tryAgain:
            start(job)
        case .chooseFolder:
            Task {
                guard let folder = await PackDestination.choose(for: activity?.name ?? job.name, startingAt: nil) else { return }
                var moved = job
                moved.destination = folder
                start(moved)
            }
        case .showInFinder, .openInStow, .openInFinder:
            dismiss()
        }
    }

    func showInFinder() {
        guard let placed = activity?.placed, !placed.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting(placed)
    }

    private func advance(to fraction: Double) {
        guard case .running(let current) = activity?.phase, fraction > current else { return }
        withAnimation(Motion.current(.linear(duration: 0.1))) { activity?.phase = .running(fraction) }
    }

    private func fadeOut(after delay: Duration) async {
        try? await Task.sleep(for: delay)
        guard !Task.isCancelled else { return }
        withAnimation(Motion.current(Motion.exit)) { activity = nil }
    }
}

/// Packing choices Stow remembers between packs.
enum PackPreferences {
    private static var defaults: UserDefaults { .standard }

    static var audience: Audience {
        get { defaults.string(forKey: "PackAudience").flatMap(Audience.init(rawValue:)) ?? .windows }
        set { defaults.set(newValue.rawValue, forKey: "PackAudience") }
    }

    /// Each audience remembers its own level.
    static func level(for audience: Audience) -> CompressionLevel {
        let key = "PackLevel.\(audience.rawValue)"
        guard defaults.object(forKey: key) != nil else { return .balanced }
        return CompressionLevel(rawValue: defaults.integer(forKey: key)) ?? .balanced
    }

    static func setLevel(_ level: CompressionLevel, for audience: Audience) {
        defaults.set(level.rawValue, forKey: "PackLevel.\(audience.rawValue)")
    }

    static var verify: Bool {
        get { defaults.bool(forKey: "PackVerify") }
        set { defaults.set(newValue, forKey: "PackVerify") }
    }

    /// `PackCPUCores`: how many cores compression may use; 0 (the default) means all of them.
    static var threads: Int? {
        let cores = defaults.integer(forKey: "PackCPUCores")
        return cores > 0 ? min(cores, ProcessInfo.processInfo.activeProcessorCount) : nil
    }
}

/// Asks where to save, and what to do when the name is taken. The folder people pick is the only
/// place Stow may write the archive (and its staging folder) to.
enum PackDestination {
    /// `severalFolders`: the items come from more than one folder, so the panel says it's asking.
    static func choose(for fileName: String, startingAt directory: URL?, severalFolders: Bool = false) async -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.prompt = String(localized: "Save Here")
        panel.message = severalFolders
            ? String(localized: "These come from several folders. Choose where to save “\(fileName)”.")
            : String(localized: "Choose where to save “\(fileName)”.")
        panel.directoryURL = directory
        let response = if let window = NSApp.keyWindow {
            await panel.beginSheetModal(for: window)
        } else {
            panel.runModal()
        }
        return response == .OK ? panel.url : nil
    }

    /// Nil when people cancel.
    static func resolveConflict(fileName: String, keepBothName: String, in folder: URL) async -> ArchiveCreation.Conflict? {
        let prompt = Prompt(symbol: "doc.on.doc.fill",
                            title: String(localized: "“\(fileName)” already exists in “\(FileManager.default.displayName(atPath: folder.path))”."),
                            message: String(localized: "Keep both and the new one is named “\(keepBothName)”. Replace moves the old one to the Trash."),
                            choices: [.init(title: String(localized: "Cancel"), role: .cancel),
                                      .init(title: String(localized: "Replace")),
                                      .init(title: String(localized: "Keep Both"), role: .primary)])
        return switch await Prompts.present(prompt).choice {
        case 2: .keepBoth
        case 1: .replace
        default: nil
        }
    }

    /// Files and folders to pack, for New Archive (⌘N).
    static func chooseSources(forAdding: Bool = false) async -> [URL] {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.prompt = forAdding ? String(localized: "Add Files") : String(localized: "Choose")
        panel.message = forAdding ? String(localized: "Choose files and folders to add.") : String(localized: "Choose files and folders to pack.")
        let response = if let window = NSApp.keyWindow {
            await panel.beginSheetModal(for: window)
        } else {
            panel.runModal()
        }
        return response == .OK ? panel.urls : []
    }
}
