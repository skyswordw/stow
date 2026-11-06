import AppKit
import Testing
@testable import Stow

@MainActor
@Suite("Tray enablement and lifetime", .serialized)
struct TrayLifecycleTests {
    @Test func delayedPresentationKeepsQuitConfirmationAboveItsParent() {
        let parent = NSWindow(contentRect: .zero, styleMask: [.titled], backing: .buffered, defer: false)
        let alert = NSPanel(contentRect: .zero, styleMask: [.titled], backing: .buffered, defer: false)
        #expect(ApplicationLifecycle.foregroundSurface(for: parent, modal: alert) === alert)
        #expect(ApplicationLifecycle.foregroundSurface(for: parent, modal: nil) === parent)
    }

    @Test func explicitWindowRequestSelectsOnlyItsOwnVisibleScene() {
        let main = NSWindow(contentRect: .zero, styleMask: [.titled], backing: .buffered, defer: false)
        let settings = NSPanel(contentRect: .zero, styleMask: [.titled], backing: .buffered, defer: false)
        main.identifier = NSUserInterfaceItemIdentifier("main-instance")
        settings.identifier = NSUserInterfaceItemIdentifier("com_apple_SwiftUI_Settings_window")
        main.orderFrontRegardless()
        settings.orderFrontRegardless()
        defer { main.orderOut(nil); settings.orderOut(nil) }
        #expect(ApplicationLifecycle.window(for: "main", in: [settings, main]) === main)
        #expect(ApplicationLifecycle.window(for: "com_apple_SwiftUI_Settings_window", in: [main, settings]) === settings)
        #expect(ApplicationLifecycle.window(for: "creation", in: [settings, main]) == nil)
        main.orderOut(nil)
        #expect(ApplicationLifecycle.window(for: "main", in: [settings, main]) == nil)
    }

    private func store() -> (UserDefaults, String) {
        let name = "TrayLifecycleTests.\(UUID())"
        return (UserDefaults(suiteName: name)!, name)
    }

    @Test func migrationSeparatesOldDefaultsFromNewInstallsAndReset() {
        let (settings, name) = store()
        defer { settings.removePersistentDomain(forName: name) }
        // Registered old defaults do not prove the application was previously installed.
        settings.register(defaults: [SettingsKeys.trayMenuBarIcon: true, SettingsKeys.trayShowWhileDragging: true])
        SettingsKeys.migrateTray(in: settings, persistent: [:])
        #expect(!SettingsKeys.flag(SettingsKeys.trayEnabled, in: settings))
        SettingsKeys.reset(.pane(.tray), in: settings)
        SettingsKeys.migrateTray(in: settings, persistent: [Onboarding.completedKey: true])
        #expect(!SettingsKeys.flag(SettingsKeys.trayEnabled, in: settings), "Reset must not repeat migration")
    }

    @Test(arguments: [(true, false, true), (false, true, true), (false, false, false)])
    func migrationPreservesExistingAvailability(icon: Bool, drag: Bool, expected: Bool) {
        let (settings, name) = store()
        defer { settings.removePersistentDomain(forName: name) }
        SettingsKeys.migrateTray(in: settings, persistent: [
            Onboarding.completedKey: true,
            SettingsKeys.trayMenuBarIcon: icon,
            SettingsKeys.trayShowWhileDragging: drag
        ])
        #expect(SettingsKeys.flag(SettingsKeys.trayEnabled, in: settings) == expected)
    }

    @Test func disablingRetainsContentsAndCannotBeUndoneByLateReveal() {
        let (settings, name) = store()
        defer { settings.removePersistentDomain(forName: name) }
        settings.set(true, forKey: SettingsKeys.trayEnabled)
        settings.set(false, forKey: SettingsKeys.trayMenuBarIcon)
        settings.set(false, forKey: SettingsKeys.trayShowWhileDragging)
        let tray = TrayController(settings: settings)
        tray.add([URL(filePath: "/tmp/retained.txt")])
        tray.show()
        tray.collectingName = "My draft"
        tray.setEnabled(false)
        tray.beginFileDrag()
        tray.show(fromDrag: true)
        #expect(!tray.isShown && !tray.hasMenuBarIcon)
        #expect(tray.collectingName == "My draft" && tray.items.count == 1)
        tray.setEnabled(true)
        #expect(!tray.isShown, "Enable is not an instruction to present")
        tray.show()
        #expect(tray.isShown && tray.items.count == 1)
        tray.hide()
    }

    @Test func firstOutsideClickRecoversAMissedDragEnd() throws {
        let (settings, name) = store()
        defer { settings.removePersistentDomain(forName: name) }
        settings.set(true, forKey: SettingsKeys.trayEnabled)
        let tray = TrayController(settings: settings)
        defer { tray.hide() }
        tray.beginFileDrag()
        tray.show(fromDrag: true)
        tray.isDropTargeted = true
        let monitor = TrayDismissalMonitor()
        monitor.canDismiss = { tray.canDismissAutomatically }
        monitor.outsidePress = { tray.reconcileOutsidePress() }
        monitor.dismiss = { tray.dismissForOutsideInteraction() }
        monitor.mouseReleased = { tray.endFileDrag(overTray: false) }
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            let event = try #require(NSEvent.mouseEvent(with: type, location: .zero, modifierFlags: [], timestamp: 0,
                windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 0))
            monitor.handle(event, local: false)
        }
        #expect(!tray.isShown, "A fresh click must not merely clear yesterday's drag state")
        tray.show()
        let picker = tray.beginRelatedInteraction()
        tray.reconcileOutsidePress()
        tray.dismissForOutsideInteraction()
        #expect(tray.isShown, "Recovering drag state must not clear a picker token")
        tray.endRelatedInteraction(picker)
    }

    @Test func lifetimeMatrixDoesNotConfuseWindowsWorkAndResidency() {
        #expect(AppLifetime.decide(hasWindow: true, hasWork: false, trayEnabled: false, mayTerminate: true) == .regular)
        #expect(AppLifetime.decide(hasWindow: false, hasWork: true, trayEnabled: false, mayTerminate: true) == .wait)
        #expect(AppLifetime.decide(hasWindow: false, hasWork: true, trayEnabled: true, mayTerminate: true) == .wait)
        #expect(AppLifetime.decide(hasWindow: false, hasWork: false, trayEnabled: true, mayTerminate: true) == .resident)
        #expect(AppLifetime.decide(hasWindow: false, hasWork: false, trayEnabled: false, mayTerminate: true) == .terminate)
        #expect(AppLifetime.decide(hasWindow: false, hasWork: false, trayEnabled: false, mayTerminate: false) == .wait)
    }
    @Test func aRunningArchiveOperationSurvivesCloseAndCanBeReopened() throws {
        let app = AppState()
        app.openArchive(named: "Working.zip")
        let model = try #require(app.browser)
        model.previewActivity(.init(step: .extract, itemCount: 1, phase: .running(0.5)))
        app.mainWindowDidClose(.browser)
        #expect(app.browser == nil && app.isBusy)
        app.prepareToShowMainWindow()
        #expect(app.browser === model && app.isBusy)
        model.previewActivity(.init(step: .extract, itemCount: 1, phase: .done))
        #expect(!app.isBusy)
    }

    @Test func resettingTrayUpdatesLiveEnablementAndPinState() {
        let (settings, name) = store()
        defer { settings.removePersistentDomain(forName: name) }
        settings.set(true, forKey: SettingsKeys.trayEnabled)
        settings.set(false, forKey: SettingsKeys.trayMenuBarIcon)
        settings.set(false, forKey: SettingsKeys.trayShowWhileDragging)
        settings.set(true, forKey: SettingsKeys.trayPinned)
        let tray = TrayController(settings: settings)
        tray.applySettings()
        #expect(tray.isEnabled && tray.isPinned)
        SettingsKeys.reset(.pane(.tray), in: settings)
        tray.applySettings()
        #expect(!tray.isEnabled && !tray.isPinned && !tray.hasMenuBarIcon)
    }

    @Test func failedBackgroundWorkRemainsAvailableForRecovery() throws {
        let app = AppState()
        app.openArchive(named: "Working.zip")
        let model = try #require(app.browser)
        model.previewActivity(.init(step: .extract, itemCount: 1, phase: .running(0.5)))
        app.mainWindowDidClose(.browser)
        let failure = Failure(EngineError(.failed, "fixture failure"), .extract, name: "Working.zip")
        model.previewActivity(.init(step: .extract, itemCount: 1, phase: .failed(failure)))
        app.releaseFinishedWork()
        #expect(!app.isBusy && app.hasLifetimeWork)
        app.prepareToShowMainWindow()
        #expect(app.browser === model)
    }

    @Test func settingsRemainsAWorkSurfaceEvenWithAUtilityWindowHost() {
        let settings = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
                               styleMask: [.titled], backing: .buffered, defer: false)
        settings.identifier = NSUserInterfaceItemIdentifier("com_apple_SwiftUI_Settings_window")
        settings.orderFrontRegardless()
        defer { settings.orderOut(nil) }
        #expect(ApplicationLifecycle.countsAsWorkWindow(settings))
        settings.orderOut(nil)
        #expect(!ApplicationLifecycle.countsAsWorkWindow(settings))
        let tray = TrayPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        tray.orderFrontRegardless()
        defer { tray.orderOut(nil) }
        #expect(!ApplicationLifecycle.countsAsWorkWindow(tray))
    }

}
