import Foundation

/// Notifies about changes to a file made by other processes (e.g. Office apps writing the registry).
final class FileWatcher {
    private var source: DispatchSourceFileSystemObject?
    private var debounce: DispatchWorkItem?
    private let onChange: () -> Void

    init?(url: URL, onChange: @escaping () -> Void) {
        let descriptor = open(url.path, O_EVTONLY)
        guard descriptor >= 0 else {
            return nil
        }
        self.onChange = onChange

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .extend, .delete, .rename],
            queue: .main
        )
        source.setEventHandler { [weak self] in
            self?.scheduleChange()
        }
        source.setCancelHandler {
            close(descriptor)
        }
        source.resume()
        self.source = source
    }

    deinit {
        debounce?.cancel()
        source?.cancel()
    }

    /// Writers usually touch the file several times in a row; coalesce them.
    private func scheduleChange() {
        debounce?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.onChange()
        }
        debounce = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }
}
