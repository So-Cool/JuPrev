import Foundation

/// Calls `onChange` (on the main queue, debounced) when the file at `url` is modified,
/// including editors' atomic saves that replace the file with a new one.
final class FileWatcher {
    private let url: URL
    private let onChange: () -> Void
    private var source: DispatchSourceFileSystemObject?
    private var debounce: DispatchWorkItem?
    /// While the file is missing, look again after this long (doubling up to 5 s).
    private var retryDelay: TimeInterval = 0.5

    init(url: URL, onChange: @escaping () -> Void) {
        self.url = url
        self.onChange = onChange
        watch()
    }

    deinit {
        debounce?.cancel()
        source?.cancel()
    }

    private func watch() {
        source?.cancel()
        source = nil
        let fd = open(url.path, O_EVTONLY)
        guard fd >= 0 else {
            // Mid-replace, or deleted (and perhaps restored later, e.g. by git): look again,
            // less and less often.
            DispatchQueue.main.asyncAfter(deadline: .now() + retryDelay) { [weak self] in self?.watch() }
            retryDelay = min(retryDelay * 2, 5)
            return
        }
        if retryDelay > 0.5 {
            // The file is back after being missing: show what's there now.
            retryDelay = 0.5
            scheduleChange()
        }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd, eventMask: [.write, .extend, .delete, .rename], queue: .main
        )
        source.setEventHandler { [weak self] in
            guard let self else { return }
            // An atomic save renames a new file over ours: the old descriptor now points
            // at the replaced file, so start watching the path afresh.
            if !source.data.isDisjoint(with: [.delete, .rename]) { self.watch() }
            self.scheduleChange()
        }
        source.setCancelHandler { close(fd) }
        source.resume()
        self.source = source
    }

    /// Editors often write in several steps; report once things settle.
    private func scheduleChange() {
        debounce?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.onChange() }
        debounce = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: work)
    }
}
