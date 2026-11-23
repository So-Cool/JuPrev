import AppKit
import NotebookKit

/// View ▸ Theme: lists the themes each time it opens, so new custom themes show up.
final class ThemeMenu: NSObject, NSMenuDelegate {
    static let shared = ThemeMenu()

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let current = JuPrevSettings.load().theme
        let themes = Themes.available()
        for theme in themes {
            if theme.isCustom, theme == themes.first(where: \.isCustom) { menu.addItem(.separator()) }
            let item = NSMenuItem(title: theme.name, action: #selector(selectTheme(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = theme.id
            item.state = theme.id == current ? .on : .off
            menu.addItem(item)
        }
        menu.addItem(.separator())
        let open = NSMenuItem(title: "Open Themes Folder", action: #selector(openThemesFolder(_:)), keyEquivalent: "")
        open.target = self
        menu.addItem(open)
    }

    @objc private func selectTheme(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        var settings = JuPrevSettings.load()
        settings.theme = id
        do {
            try settings.save()
            NotificationCenter.default.post(name: .juprevSettingsDidChange, object: nil)
        } catch {
            NSApp.presentError(error)
        }
    }

    @objc func openThemesFolder(_ sender: Any?) {
        Self.openThemesFolder()
    }

    /// Creates the folder on first use, so there's somewhere to put .css files.
    static func openThemesFolder() {
        do {
            try FileManager.default.createDirectory(at: Themes.customFolder, withIntermediateDirectories: true)
            NSWorkspace.shared.open(Themes.customFolder)
        } catch {
            NSApp.presentError(error)
        }
    }
}
