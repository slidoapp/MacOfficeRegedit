import AppKit
import Observation

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

    /// Written once in `init` and read in `deinit`, when nothing else can reference the monitor.
    @ObservationIgnored private nonisolated(unsafe) var observers: [NSObjectProtocol] = []

    init() {
        refresh()
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                // Delivered on the main queue, so update synchronously instead of hopping through a Task.
                MainActor.assumeIsolated {
                    self?.refresh()
                }
            })
        }
    }

    deinit {
        observers.forEach(NSWorkspace.shared.notificationCenter.removeObserver)
    }

    private func refresh() {
        let names = NSWorkspace.shared.runningApplications.compactMap { app in
            app.bundleIdentifier.flatMap { OfficeAppsMonitor.bundleIdentifiers[$0] }
        }
        runningApps = Array(Set(names)).sorted()
    }
}
