import AppKit
import SwiftUI

final class NotebookWindowController: NSWindowController, NSMenuItemValidation {
    private static let outlineVisibleKey = "OutlineVisible"

    private let notebookViewController: NotebookViewController
    private let splitViewController = NSSplitViewController()
    private let outlineItem: NSSplitViewItem

    init(document: NotebookDocument) {
        let outline = OutlineModel()
        notebookViewController = NotebookViewController(document: document, outline: outline)

        outlineItem = NSSplitViewItem(sidebarWithViewController: NSHostingController(rootView: OutlineView(model: outline)))
        outlineItem.minimumThickness = 180
        outlineItem.maximumThickness = 400
        outlineItem.canCollapse = true
        outlineItem.isCollapsed = !UserDefaults.standard.bool(forKey: Self.outlineVisibleKey)
        splitViewController.addSplitViewItem(outlineItem)
        splitViewController.addSplitViewItem(NSSplitViewItem(viewController: notebookViewController))
        notebookViewController.outlineVisible = !outlineItem.isCollapsed

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 1000),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: true
        )
        window.contentViewController = splitViewController
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
        switch item.action {
        case #selector(findInNotebook(_:)):
            return notebookViewController.canFind
        case #selector(toggleCode(_:)):
            item.state = notebookViewController.showCode ? .on : .off
        case #selector(toggleOutputs(_:)):
            item.state = notebookViewController.showOutputs ? .on : .off
        case #selector(toggleOutline(_:)):
            item.title = outlineItem.isCollapsed ? "Show Outline" : "Hide Outline"
        default:
            break
        }
        return true
    }

    // MARK: View menu (sent up the responder chain from the window)

    @objc func reloadNotebook(_ sender: Any?) { notebookViewController.reload(preservingScroll: true) }

    // Edit ▸ Find (tags are NSTextFinder.Action values). A selector of our own: with the
    // standard performTextFinderAction(_:), WKWebView (first responder) takes the action.
    @objc func findInNotebook(_ sender: Any?) { notebookViewController.runFindAction(sender) }
    @objc func toggleOutline(_ sender: Any?) {
        outlineItem.animator().isCollapsed.toggle()
        let visible = !outlineItem.isCollapsed
        notebookViewController.outlineVisible = visible
        // New windows open the way the last one was left.
        UserDefaults.standard.set(visible, forKey: Self.outlineVisibleKey)
    }

    // File menu
    @objc func exportHTML(_ sender: Any?) { notebookViewController.exportHTML() }
    @objc func exportPDF(_ sender: Any?) { notebookViewController.exportPDF() }
    @objc func printNotebook(_ sender: Any?) { notebookViewController.printNotebook() }

    @objc func toggleCode(_ sender: Any?) { notebookViewController.toggleCode() }
    @objc func toggleOutputs(_ sender: Any?) { notebookViewController.toggleOutputs() }
    @objc func actualSize(_ sender: Any?) { notebookViewController.zoom(to: 1) }
    @objc func zoomIn(_ sender: Any?) { notebookViewController.zoom(by: 1.1) }
    @objc func zoomOut(_ sender: Any?) { notebookViewController.zoom(by: 1 / 1.1) }
}
