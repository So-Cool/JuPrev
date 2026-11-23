import AppKit

final class NotebookWindowController: NSWindowController, NSMenuItemValidation {
    private let notebookViewController: NotebookViewController

    init(document: NotebookDocument) {
        notebookViewController = NotebookViewController(document: document)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 1000),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: true
        )
        window.contentViewController = notebookViewController
        window.setContentSize(NSSize(width: 900, height: 1000))
        window.minSize = NSSize(width: 420, height: 300)
        window.titlebarSeparatorStyle = .line
        window.tabbingMode = .preferred
        super.init(window: window)
        shouldCascadeWindows = true
        window.center()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        if item.action == #selector(findInNotebook(_:)) {
            return notebookViewController.canFind
        }
        return true
    }

    // MARK: View menu (sent up the responder chain from the window)

    @objc func reloadNotebook(_ sender: Any?) { notebookViewController.reload(preservingScroll: true) }

    // Edit ▸ Find (tags are NSTextFinder.Action values). A selector of our own: with the
    // standard performTextFinderAction(_:), WKWebView (first responder) takes the action.
    @objc func findInNotebook(_ sender: Any?) { notebookViewController.runFindAction(sender) }
    @objc func actualSize(_ sender: Any?) { notebookViewController.zoom(to: 1) }
    @objc func zoomIn(_ sender: Any?) { notebookViewController.zoom(by: 1.1) }
    @objc func zoomOut(_ sender: Any?) { notebookViewController.zoom(by: 1 / 1.1) }
}
