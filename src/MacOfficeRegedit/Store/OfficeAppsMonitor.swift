import AppKit

/// Tracks running Office apps. They read the registry at launch and may overwrite edits when they quit.
@MainActor
final class OfficeAppsMonitor: ObservableObject {
    static let bundleIdentifiers: [String: String] = [
        "com.microsoft.Word": "Word",
        "com.microsoft.Excel": "Excel",
        "com.microsoft.Powerpoint": "PowerPoint",
        "com.microsoft.Outlook": "Outlook",
        "com.microsoft.onenote.mac": "OneNote",
    ]

    @Published private(set) var runningApps: [String] = []

    private var observers: [NSObjectProtocol] = []

    init() {
        refresh()
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in
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
