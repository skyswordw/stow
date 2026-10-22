import Foundation

/// "Installs wait until running tasks finish" (#35): when Sparkle is ready to quit and relaunch
/// into an update while Stow is extracting, packing or opening something, the relaunch is held
/// and resumes by itself once Stow is idle.
final class UpdateInstallGate {
    var isBusy: () -> Bool = { false }
    var pollInterval: Duration = .seconds(2)
    private(set) var pending: (() -> Void)?
    private var waiter: Task<Void, Never>?

    /// `true` when the install was postponed (Sparkle then waits for the handler).
    func postpone(_ install: @escaping () -> Void) -> Bool {
        guard isBusy() else { return false }
        pending = install
        waiter?.cancel()
        waiter = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: self?.pollInterval ?? .seconds(2))
                guard let self else { return }
                if self.resumeIfIdle() { return }
            }
        }
        return true
    }

    /// Runs a held install once Stow is idle. `true` once nothing is held any more.
    @discardableResult
    func resumeIfIdle() -> Bool {
        guard let install = pending else { return true }
        guard !isBusy() else { return false }
        pending = nil
        install()
        return true
    }
}
