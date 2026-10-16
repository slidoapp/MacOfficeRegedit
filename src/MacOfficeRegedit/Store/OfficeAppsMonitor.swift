import AppKit
import Observation
import Synchronization

/// Tracks running Office apps. They read the registry at launch and may overwrite edits when they quit.
@MainActor
@Observable
final class OfficeAppsMonitor {
    static let bundleIdentifiers: [String: String] = [
        "com.microsoft.Word": "Word",
        "com.microsoft.Excel": "Excel",
        "com.microsoft.Powerpoint": "PowerPoint",
        "com.microsoft.Outlook": "Outlook",
        "com.microsoft.onenote.mac": "OneNote",
    ]

    private(set) var runningApps: [String] = []

    /// Tasks listening for app launches and terminations; cancelled in `deinit`. A `Mutex`, because the
    /// nonisolated `deinit` reads it.
    private let listeners = Mutex<[Task<Void, Never>]>([])

    init() {
        refresh()
        let center = NSWorkspace.shared.notificationCenter
        let tasks = [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification].map { name in
            // Inherits the main actor, so `refresh()` runs on it.
            Task { [weak self] in
                for await _ in center.notifications(named: name) {
                    self?.refresh()
                }
            }
        }
        listeners.withLock { $0 = tasks }
    }

    deinit {
        listeners.withLock { tasks in
            tasks.forEach { $0.cancel() }
        }
    }

    private func refresh() {
        let names = NSWorkspace.shared.runningApplications.compactMap { app in
            app.bundleIdentifier.flatMap { OfficeAppsMonitor.bundleIdentifiers[$0] }
        }
        runningApps = Array(Set(names)).sorted()
    }
}
