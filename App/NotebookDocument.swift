import AppKit
import NotebookKit

/// A read-only notebook. JuPrev is a viewer: documents are never edited or saved.
final class NotebookDocument: NSDocument {
    private(set) var contents = Data()

    override class var autosavesInPlace: Bool { false }

    override func read(from data: Data, ofType typeName: String) throws {
        contents = data
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
