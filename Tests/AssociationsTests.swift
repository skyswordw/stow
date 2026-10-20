import AppKit
import Testing
import UniformTypeIdentifiers
@testable import Stow

/// A pretend Launch Services: defaults per type, apps by bundle identifier, and switches for the
/// two ways a change can fail (an error, or macOS quietly keeping the old app).
private final class FakeRegistry: DefaultAppRegistry {
    var defaults: [String: URL] = [:]
    var installed: [String: URL] = [:]
    var refuse: Set<String> = []
    var ignore: Set<String> = []
    private(set) var calls: [(String, URL)] = []

    func defaultApp(for type: UTType) -> URL? { defaults[type.identifier] }

    func setDefaultApp(_ app: URL, for type: UTType) async throws {
        calls.append((type.identifier, app))
        if refuse.contains(type.identifier) {
            throw NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError,
                          userInfo: [NSLocalizedDescriptionKey: "You chose to keep the current app."])
        }
        if !ignore.contains(type.identifier) { defaults[type.identifier] = app }
    }

    func app(withBundleIdentifier identifier: String) -> URL? { installed[identifier] }

    func bundleIdentifier(of app: URL) -> String? {
        installed.first { $0.value == app }?.key
    }
}

@Suite("File associations")
@MainActor
struct AssociationsTests {
    let stow = URL(filePath: "/Applications/Stow.app")
    let utility = URL(filePath: "/System/Library/CoreServices/Applications/Archive Utility.app")
    let keka = URL(filePath: "/Applications/Keka.app")
    let zip = "public.zip-archive", sevenZip = "org.7-zip.7-zip-archive", rar = "com.rarlab.rar-archive"

    private func make(_ registry: FakeRegistry) -> Associations {
        registry.installed = ["app.stow.Stow": stow, Associations.archiveUtility: utility, "com.aone.keka": keka]
        let defaults = UserDefaults(suiteName: "AssociationsTests-\(UUID().uuidString)")!
        return Associations(registry: registry, stow: stow, stowIdentifier: "app.stow.Stow", defaults: defaults)
    }

    @Test func remembersThePreviousAppAndSwitchesBack() async {
        let registry = FakeRegistry()
        registry.defaults = [zip: keka, sevenZip: utility]
        let model = make(registry)
        model.selection = [zip, sevenZip]

        await model.makeStowDefault()
        #expect(registry.defaults[zip] == stow && registry.defaults[sevenZip] == stow)
        #expect(model.report?.changed.count == 2 && model.report?.isSuccess == true)
        #expect(model.rows.first { $0.id == zip }?.previous == "com.aone.keka")

        await model.restorePrevious()
        #expect(registry.defaults[zip] == keka)
        #expect(registry.defaults[sevenZip] == utility)
        #expect(model.report?.kind == .restored && model.report?.changed.count == 2)
        #expect(model.rows.first { $0.id == zip }?.previous == nil)
    }

    @Test func alreadyStowIsLeftAloneAndKeepsTheOlderPrevious() async {
        let registry = FakeRegistry()
        registry.defaults = [zip: keka]
        let model = make(registry)
        model.selection = [zip]
        await model.makeStowDefault()
        await model.makeStowDefault() // again: must not record Stow as its own "previous"
        #expect(model.report?.unchanged == ["ZIP archive"])
        #expect(model.rows.first { $0.id == zip }?.previous == "com.aone.keka")
        #expect(registry.calls.count == 1)
    }

    @Test func reportsRefusalsAndQuietlyKeptApps() async {
        let registry = FakeRegistry()
        registry.defaults = [zip: utility, sevenZip: utility, rar: utility]
        registry.refuse = [sevenZip]
        registry.ignore = [rar]
        let model = make(registry)
        model.selection = [zip, sevenZip, rar]
        await model.makeStowDefault()
        let report = try! #require(model.report)
        #expect(report.changed == ["ZIP archive"])
        #expect(report.failed["7-Zip archive"] == "You chose to keep the current app.")
        #expect(report.failed["RAR archive"] == "macOS kept Archive Utility.")
        #expect(!report.isSuccess)
        #expect(report.summary == "1 type now open with Stow · 2 types not changed")
    }

    @Test func noPreviousAppFallsBackToArchiveUtility() async {
        let registry = FakeRegistry()
        registry.defaults = [rar: stow] // e.g. Stow was the first app that could open RAR
        let model = make(registry)
        model.selection = [rar]
        await model.restorePrevious()
        #expect(registry.defaults[rar] == utility)
    }

    @Test func uninstalledPreviousAppIsExplained() async {
        let registry = FakeRegistry()
        registry.defaults = [zip: keka]
        let model = make(registry)
        model.selection = [zip]
        await model.makeStowDefault()
        registry.installed["com.aone.keka"] = nil
        await model.restorePrevious()
        #expect(model.report?.failed["ZIP archive"]?.contains("isn’t installed") == true)
        #expect(registry.defaults[zip] == stow)
    }

    @Test func suggestedSkipsDiskImagesAndInstallers() {
        let model = make(FakeRegistry())
        model.selectSuggested()
        #expect(model.selection.contains(zip))
        #expect(!model.selection.contains("com.apple.disk-image-udif"))
        #expect(!model.selection.contains("com.apple.installer-package-archive"))
    }

    @Test func dockHidesOnlyWhenAskedAndNoWindowsAreLeft() {
        #expect(DockPolicy.shouldHide(setting: true, openWindows: 0))
        #expect(!DockPolicy.shouldHide(setting: true, openWindows: 1))
        #expect(!DockPolicy.shouldHide(setting: false, openWindows: 0))
    }
}
