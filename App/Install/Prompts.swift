import AppKit

/// The questions extraction and installs ask, as native alert sheets on the front window. Safe
/// choices are the default button; nothing destructive happens on Return alone.
enum Prompts {
    static func ask(_ question: Installer.Question) async -> Installer.Answer {
        let alert = NSAlert()
        switch question {
        case .signature(let app, let verdict):
            let finding = verdict.finding
            alert.alertStyle = verdict == .broken ? .critical : .warning
            alert.messageText = verdict.headline(app: Installer.displayName(app))
            alert.informativeText = finding.detail + " Install it anyway?"
            alert.addButton(withTitle: "Cancel")
            alert.addButton(withTitle: "Install Anyway")
            return await run(alert) == .alertSecondButtonReturn ? .proceed : .cancel
        case .replaceApp(let app, let installed, let incoming):
            let name = Installer.displayName(app)
            alert.messageText = "Replace the installed “\(name)”?"
            alert.informativeText = switch (installed, incoming) {
            case let (old?, new?) where old == new:
                "Both are version \(old). The installed one moves to the Trash."
            case let (old?, new?):
                "Version \(old) moves to the Trash and version \(new) takes its place."
            default:
                "The installed one moves to the Trash, so you can put it back."
            }
            alert.addButton(withTitle: "Replace")
            alert.addButton(withTitle: "Keep Both")
            alert.addButton(withTitle: "Cancel")
        case .replaceFonts(let names):
            alert.messageText = names.count == 1 ? "“\(names[0])” is already installed."
                : "\(names.count) of these fonts are already installed."
            alert.informativeText = "Replacing moves the installed copies to the Trash. Skip installs only the new ones."
            alert.addButton(withTitle: "Replace")
            alert.addButton(withTitle: "Skip")
            alert.addButton(withTitle: "Cancel")
        }
        return switch await run(alert) {
        case .alertFirstButtonReturn: .proceed
        case .alertSecondButtonReturn: .alternate
        default: .cancel
        }
    }

    /// Nil means stop (and undo).
    static func resolve(_ conflict: Placement.Conflict) async -> (Placement.Resolution, forAll: Bool)? {
        let alert = NSAlert()
        let folder = FileManager.default.displayName(atPath: conflict.existing.deletingLastPathComponent().path)
        let choices: [Placement.Resolution]
        if conflict.canMerge {
            alert.messageText = "A folder named “\(conflict.name)” is already in “\(folder)”."
            alert.informativeText = "Merge adds what’s new to it and asks before replacing any file. Keep Both adds this one as “\(Extraction.numbered(conflict.name, 2))”."
            choices = [.merge, .keepBoth]
            alert.addButton(withTitle: "Merge")
            alert.addButton(withTitle: "Keep Both")
        } else {
            alert.messageText = "“\(conflict.name)” is already in “\(folder)”."
            alert.informativeText = "Existing: \(describe(conflict.existing)). Extracted: \(describe(conflict.incoming)). Replacing moves the existing one to the Trash."
            choices = [.replace, .keepBoth, .skip]
            alert.addButton(withTitle: "Replace")
            alert.addButton(withTitle: "Keep Both")
            alert.addButton(withTitle: "Skip")
        }
        alert.addButton(withTitle: "Stop")
        alert.showsSuppressionButton = true
        alert.suppressionButton?.title = conflict.canMerge ? "Do the same for other folders" : "Do the same for other files"
        let response = await run(alert)
        let index = response.rawValue - NSApplication.ModalResponse.alertFirstButtonReturn.rawValue
        guard choices.indices.contains(index) else { return nil }
        return (choices[index], alert.suppressionButton?.state == .on)
    }

    /// Whether to move the archive(s) to the Trash, and whether to stop asking.
    static func trashArchives(_ names: [String], after action: String) async -> (trash: Bool, remember: Bool) {
        let alert = NSAlert()
        alert.messageText = names.count == 1 ? "Move “\(names[0])” to the Trash?" : "Move \(names.count) archives to the Trash?"
        alert.informativeText = "\(action) You can put \(names.count == 1 ? "it" : "them") back from the Trash."
        alert.addButton(withTitle: "Keep")
        alert.addButton(withTitle: "Move to Trash")
        alert.showsSuppressionButton = true
        alert.suppressionButton?.title = "Don’t ask again"
        let trash = await run(alert) == .alertSecondButtonReturn
        return (trash, alert.suppressionButton?.state == .on)
    }

    static func describe(_ url: URL) -> String {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey, .isDirectoryKey])
        let kind = values?.isDirectory == true ? "folder" : Int64(values?.fileSize ?? 0).bytes
        let date = values?.contentModificationDate?.formatted(date: .abbreviated, time: .shortened) ?? "unknown date"
        return "\(kind), \(date)"
    }

    @discardableResult
    static func run(_ alert: NSAlert) async -> NSApplication.ModalResponse {
        // A sheet on Stow's window even when Stow is in the background — an app-modal alert would
        // stop everything else (progress, the batch queue) until it's answered.
        let window = [NSApp.keyWindow, NSApp.mainWindow].compactMap(\.self).first { !($0 is NSPanel) }
            ?? NSApp.windows.first { $0.isVisible && !($0 is NSPanel) && $0.sheetParent == nil }
        if let window, window.attachedSheet == nil {
            return await alert.beginSheetModal(for: window)
        }
        return alert.runModal()
    }
}

/// Applies the conflict settings, asks when they say "ask", and remembers "do the same" for the
/// rest of one extraction (or batch).
final class ConflictPolicy {
    private var folder: Preferences.FolderConflict
    private var file: Preferences.FileConflict
    private let ask: (Placement.Conflict) async -> (Placement.Resolution, forAll: Bool)?

    init(_ values: Preferences.Values = Preferences.current,
         ask: @escaping (Placement.Conflict) async -> (Placement.Resolution, forAll: Bool)? = Prompts.resolve) {
        folder = values.folderConflict
        file = values.fileConflict
        self.ask = ask
    }

    var resolver: Placement.Resolver {
        { conflict throws(EngineError) in try await self.resolve(conflict) }
    }

    func resolve(_ conflict: Placement.Conflict) async throws(EngineError) -> Placement.Resolution {
        if conflict.canMerge {
            switch folder {
            case .merge: return .merge
            case .keepBoth: return .keepBoth
            case .ask: break
            }
        } else {
            switch file {
            case .replace: return .replace
            case .keepBoth: return .keepBoth
            case .skip: return .skip
            case .ask: break
            }
        }
        guard let (answer, forAll) = await ask(conflict) else { throw EngineError(.cancelled) }
        if forAll {
            if conflict.canMerge {
                folder = answer == .merge ? .merge : .keepBoth
            } else {
                file = switch answer {
                case .replace: .replace
                case .skip: .skip
                default: .keepBoth
                }
            }
        }
        return answer
    }
}

/// Keep, trash or ask about the archive once its contents are out.
enum ArchiveAftercare {
    /// Returns the archives that went to the Trash.
    static func apply(_ setting: Preferences.AfterwardsArchive, key: String, to archives: [URL],
                      action: String) async -> [URL] {
        guard !archives.isEmpty else { return [] }
        var trash = setting == .trash
        if setting == .ask {
            let answer = await Prompts.trashArchives(archives.map(\.lastPathComponent), after: action)
            trash = answer.trash
            if answer.remember { Preferences.set(trash ? Preferences.AfterwardsArchive.trash : .keep, for: key) }
        }
        guard trash else { return [] }
        return archives.filter { (try? FileManager.default.trashItem(at: $0, resultingItemURL: nil)) != nil }
    }
}
