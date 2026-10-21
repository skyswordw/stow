import AppKit
import SwiftUI

/// The questions extraction, installs and packing ask, as `PromptCard` sheets on the front window
/// — the same look as the password sheet and failures. Safe choices are the default button;
/// nothing destructive happens on Return alone.
enum Prompts {
    static func ask(_ question: Installer.Question) async -> Installer.Answer {
        let prompt: Prompt
        let cancel = Prompt.Choice(title: String(localized: "Cancel"), role: .cancel)
        switch question {
        case .signature(let app, let verdict):
            let finding = verdict.finding
            prompt = Prompt(symbol: verdict == .broken ? "xmark.shield.fill" : "exclamationmark.shield.fill",
                            tint: verdict == .broken ? .red : .yellow,
                            title: verdict.headline(app: Installer.displayName(app)),
                            message: finding.detail + String(localized: " Install it anyway?"),
                            choices: [.init(title: String(localized: "Install Anyway")),
                                      .init(title: String(localized: "Cancel"), role: .primary)])
            // Cancel is the safe default here; Escape answers it too.
            let answer = await present(prompt)
            return answer.choice == 0 ? .proceed : .cancel
        case .replaceApp(let app, let installed, let incoming):
            let name = Installer.displayName(app)
            var details: [(String, String)] = []
            if let installed { details.append((String(localized: "Installed"), String(localized: "Version \(installed)"))) }
            if let incoming { details.append((String(localized: "In the archive"), String(localized: "Version \(incoming)"))) }
            let message = switch (installed, incoming) {
            case let (old?, new?) where old == new:
                String(localized: "Both are version \(old). The installed one moves to the Trash.")
            case let (old?, new?):
                String(localized: "Version \(old) moves to the Trash and version \(new) takes its place.")
            default:
                String(localized: "The installed one moves to the Trash, so you can put it back.")
            }
            prompt = Prompt(symbol: "square.and.arrow.down.on.square.fill", title: String(localized: "Replace the installed “\(name)”?"),
                            message: message, details: details,
                            choices: [cancel, .init(title: String(localized: "Keep Both")),
                                      .init(title: String(localized: "Replace"), role: .primary)])
        case .replaceFonts(let names):
            prompt = Prompt(symbol: "textformat",
                            title: names.count == 1 ? String(localized: "“\(names[0])” is already installed.")
                                : String(localized: "\(names.count) of these fonts are already installed."),
                            message: String(localized: "Replacing moves the installed copies to the Trash. Skip installs only the new ones."),
                            choices: [cancel, .init(title: String(localized: "Skip")),
                                      .init(title: String(localized: "Replace"), role: .primary)])
        }
        return switch await present(prompt).choice {
        case 2: .proceed
        case 1: .alternate
        default: .cancel
        }
    }

    /// Nil means stop (and undo).
    static func resolve(_ conflict: Placement.Conflict) async -> (Placement.Resolution, forAll: Bool)? {
        let folder = FileManager.default.displayName(atPath: conflict.existing.deletingLastPathComponent().path)
        let stop = Prompt.Choice(title: String(localized: "Stop"), role: .cancel)
        let prompt: Prompt
        let choices: [Placement.Resolution?]
        if conflict.canMerge {
            prompt = Prompt(symbol: "folder.fill",
                            title: String(localized: "A folder named “\(conflict.name)” is already in “\(folder)”."),
                            message: String(localized: "Merge puts the extracted contents into it; files already there stay unless you choose to replace them. Keep Both adds this one as “\(Extraction.numbered(conflict.name, 2))”."),
                            choices: [stop, .init(title: String(localized: "Keep Both")),
                                      .init(title: String(localized: "Merge"), role: .primary)],
                            suppression: String(localized: "Do the same for other folders"))
            choices = [nil, .keepBoth, .merge]
        } else {
            prompt = Prompt(symbol: "doc.on.doc.fill",
                            title: String(localized: "“\(conflict.name)” is already in “\(folder)”."),
                            message: String(localized: "Keep Both adds this one as “\(Extraction.numbered(conflict.name, 2))”. Replacing moves the existing one to the Trash."),
                            details: [(String(localized: "Existing"), describe(conflict.existing)),
                                      (String(localized: "Extracted"), describe(conflict.incoming))],
                            choices: [stop, .init(title: String(localized: "Skip")), .init(title: String(localized: "Replace")),
                                      .init(title: String(localized: "Keep Both"), role: .primary)],
                            suppression: String(localized: "Do the same for other files"))
            choices = [nil, .skip, .replace, .keepBoth]
        }
        let answer = await present(prompt)
        guard let resolution = choices[answer.choice] else { return nil }
        return (resolution, answer.suppress)
    }

    /// Whether to move the archive(s) to the Trash, and whether to stop asking.
    static func trashArchives(_ names: [String], after action: String) async -> (trash: Bool, remember: Bool) {
        let prompt = Prompt(symbol: "trash",
                            title: names.count == 1 ? String(localized: "Move “\(names[0])” to the Trash?") : String(localized: "Move \(names.count) archives to the Trash?"),
                            message: String(localized: "\(action) You can put \(names.count == 1 ? String(localized: "it") : String(localized: "them")) back from the Trash."),
                            choices: [.init(title: String(localized: "Move to Trash")),
                                      .init(title: String(localized: "Keep"), role: .primary)],
                            suppression: String(localized: "Don’t ask again"))
        let answer = await present(prompt)
        return (answer.choice == 0, answer.suppress)
    }

    static func describe(_ url: URL) -> String {
        guard let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey, .isDirectoryKey]) else {
            return String(localized: "no details")
        }
        let kind = values.isDirectory == true ? String(localized: "folder") : Int64(values.fileSize ?? 0).bytes
        let date = values.contentModificationDate?.formatted(date: .abbreviated, time: .shortened) ?? String(localized: "unknown date")
        return String(localized: "\(kind), \(date)")
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
