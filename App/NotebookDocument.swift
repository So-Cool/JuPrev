import AppKit
import NotebookKit

/// A read-only notebook. JuPrev is a viewer: documents are never edited or saved,
/// but they follow changes made to the file by other apps (live reload).
final class NotebookDocument: NSDocument {
    static let contentsDidChange = Notification.Name("NotebookDocumentContentsDidChange")

    private(set) var contents = Data() {
        didSet {
            if contents != oldValue { NotificationCenter.default.post(name: Self.contentsDidChange, object: self) }
        }
    }

    private var watcher: FileWatcher?

    override class var autosavesInPlace: Bool { false }

    override func read(from data: Data, ofType typeName: String) throws {
        contents = data
    }

    override var fileURL: URL? {
        didSet { startWatching() }
    }

    private func startWatching() {
        guard let url = fileURL else {
            watcher = nil
            return
        }
        watcher = FileWatcher(url: url) { [weak self] in self?.reloadFromDisk() }
    }

    /// Keeps showing the last good contents if the file is gone or mid-write.
    private func reloadFromDisk() {
        guard let url = fileURL, let data = try? Data(contentsOf: url), !data.isEmpty else { return }
        contents = data
    }

    override func close() {
        watcher = nil
        super.close()
    }

    override func data(ofType typeName: String) throws -> Data {
        throw CocoaError(.featureUnsupported)
    }

    override func makeWindowControllers() {
        addWindowController(NotebookWindowController(document: self))
    }
}

/// Serializes access to one NotebookRenderer (it isn't thread-safe) and keeps rendering
/// off the main thread.
final class RenderService: @unchecked Sendable {
    static let shared = RenderService()

    private let queue = DispatchQueue(label: "me.kcpr.juprev.render", qos: .userInitiated)
    private var renderer: NotebookRenderer?

    func render(_ data: Data, fileURL: URL?, options: RenderOptions) async -> Result<RenderedNotebook, Error> {
        await withCheckedContinuation { continuation in
            queue.async {
                continuation.resume(returning: Result {
                    if self.renderer == nil { self.renderer = try NotebookRenderer() }
                    return try self.renderer!.render(
                        data: data,
                        notebookFolder: fileURL?.deletingLastPathComponent(),
                        fallbackTitle: fileURL?.deletingPathExtension().lastPathComponent,
                        options: options
                    )
                })
            }
        }
    }
}
