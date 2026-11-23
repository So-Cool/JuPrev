import AppKit

/// The menu bar, built in code (the app has no nib). Actions go to the first responder;
/// notebook-specific ones are handled by `NotebookWindowController`.
enum MainMenu {
    static func make() -> NSMenu {
        let main = NSMenu()
        main.addItem(submenu(appMenu()))
        main.addItem(submenu(fileMenu()))
        main.addItem(submenu(editMenu()))
        main.addItem(submenu(viewMenu()))
        let window = windowMenu()
        main.addItem(submenu(window))
        NSApp.windowsMenu = window
        let help = NSMenu(title: "Help")
        main.addItem(submenu(help))
        NSApp.helpMenu = help
        return main
    }

    private static func submenu(_ menu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem(title: menu.title, action: nil, keyEquivalent: "")
        item.submenu = menu
        return item
    }

    private static func item(_ title: String, _ action: Selector?, _ key: String = "", _ modifiers: NSEvent.ModifierFlags = .command) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = modifiers
        return item
    }

    private static func appMenu() -> NSMenu {
        let menu = NSMenu(title: "JuPrev")
        menu.addItem(item("About JuPrev", #selector(AppDelegate.showAbout(_:))))
        menu.addItem(.separator())
        menu.addItem(item("Settings…", #selector(AppDelegate.showSettings(_:)), ","))
        menu.addItem(.separator())
        let services = NSMenu(title: "Services")
        menu.addItem(submenu(services))
        NSApp.servicesMenu = services
        menu.addItem(.separator())
        menu.addItem(item("Hide JuPrev", #selector(NSApplication.hide(_:)), "h"))
        menu.addItem(item("Hide Others", #selector(NSApplication.hideOtherApplications(_:)), "h", [.command, .option]))
        menu.addItem(item("Show All", #selector(NSApplication.unhideAllApplications(_:))))
        menu.addItem(.separator())
        menu.addItem(item("Quit JuPrev", #selector(NSApplication.terminate(_:)), "q"))
        return menu
    }

    private static func fileMenu() -> NSMenu {
        let menu = NSMenu(title: "File")
        menu.addItem(item("Open…", #selector(NSDocumentController.openDocument(_:)), "o"))
        let recent = NSMenu(title: "Open Recent")
        recent.delegate = RecentDocumentsMenu.shared
        menu.addItem(submenu(recent))
        menu.addItem(.separator())
        menu.addItem(item("Close", #selector(NSWindow.performClose(_:)), "w"))
        return menu
    }

    private static func editMenu() -> NSMenu {
        let menu = NSMenu(title: "Edit")
        menu.addItem(item("Copy", #selector(NSText.copy(_:)), "c"))
        menu.addItem(item("Select All", #selector(NSText.selectAll(_:)), "a"))
        menu.addItem(.separator())
        menu.addItem(submenu(findMenu()))
        return menu
    }

    private static func findMenu() -> NSMenu {
        let menu = NSMenu(title: "Find")
        let finder = #selector(NotebookWindowController.findInNotebook(_:))
        let entries: [(String, String, NSEvent.ModifierFlags, NSTextFinder.Action)] = [
            ("Find…", "f", .command, .showFindInterface),
            ("Find Next", "g", .command, .nextMatch),
            ("Find Previous", "g", [.command, .shift], .previousMatch),
            ("Use Selection for Find", "e", .command, .setSearchString),
        ]
        for (title, key, modifiers, action) in entries {
            let entry = item(title, finder, key, modifiers)
            entry.tag = action.rawValue
            menu.addItem(entry)
        }
        return menu
    }

    private static func viewMenu() -> NSMenu {
        let menu = NSMenu(title: "View")
        menu.addItem(item("Reload", #selector(NotebookWindowController.reloadNotebook(_:)), "r"))
        menu.addItem(.separator())
        menu.addItem(item("Show Code", #selector(NotebookWindowController.toggleCode(_:)), "c", [.command, .option]))
        menu.addItem(item("Show Outputs", #selector(NotebookWindowController.toggleOutputs(_:)), "o", [.command, .option]))
        menu.addItem(.separator())
        menu.addItem(item("Actual Size", #selector(NotebookWindowController.actualSize(_:)), "0"))
        menu.addItem(item("Zoom In", #selector(NotebookWindowController.zoomIn(_:)), "+"))
        menu.addItem(item("Zoom Out", #selector(NotebookWindowController.zoomOut(_:)), "-"))
        menu.addItem(.separator())
        menu.addItem(item("Enter Full Screen", #selector(NSWindow.toggleFullScreen(_:)), "f", [.command, .control]))
        return menu
    }

    private static func windowMenu() -> NSMenu {
        let menu = NSMenu(title: "Window")
        menu.addItem(item("Minimize", #selector(NSWindow.performMiniaturize(_:)), "m"))
        menu.addItem(item("Zoom", #selector(NSWindow.performZoom(_:))))
        menu.addItem(.separator())
        menu.addItem(item("Bring All to Front", #selector(NSApplication.arrangeInFront(_:))))
        return menu
    }
}

/// Fills File ▸ Open Recent from NSDocumentController each time it opens.
final class RecentDocumentsMenu: NSObject, NSMenuDelegate {
    static let shared = RecentDocumentsMenu()

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        for url in NSDocumentController.shared.recentDocumentURLs {
            let item = NSMenuItem(title: url.lastPathComponent, action: #selector(openRecent(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = url
            item.image = NSWorkspace.shared.icon(forFile: url.path)
            item.image?.size = NSSize(width: 16, height: 16)
            menu.addItem(item)
        }
        if !menu.items.isEmpty { menu.addItem(.separator()) }
        let clear = NSMenuItem(title: "Clear Menu", action: #selector(NSDocumentController.clearRecentDocuments(_:)), keyEquivalent: "")
        menu.addItem(clear)
    }

    @objc private func openRecent(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, error in
            if let error { NSApp.presentError(error) }
        }
    }
}
