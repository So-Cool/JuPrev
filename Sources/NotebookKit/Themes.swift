import Foundation

/// A stylesheet applied after the base style: bundled ("serif") or the user's own
/// ("custom:name.css" in `Themes.customFolder`).
public struct Theme: Equatable, Hashable, Sendable {
    public static let defaultID = "default"

    public let id: String
    public let name: String
    public let isCustom: Bool
}

public enum Themes {
    static let bundled: [(id: String, name: String)] = [
        ("serif", "Serif"),
        ("compact", "Compact"),
        ("gruvbox-dark", "Gruvbox Material Dark"),
        ("gruvbox-light", "Gruvbox Material Light"),
    ]
    static let customPrefix = "custom:"
    static let maxCSSBytes = 1024 * 1024

    /// `~/Library/Application Support/JuPrev/Themes`, next to the settings file.
    public static var customFolder: URL {
        JuPrevSettings.defaultFileURL.deletingLastPathComponent().appendingPathComponent("Themes", isDirectory: true)
    }

    /// Default first, then the bundled themes, then custom ones by name.
    public static func available(customFolder: URL = customFolder) -> [Theme] {
        let builtIn = [Theme(id: Theme.defaultID, name: "Default", isCustom: false)]
            + bundled.map { Theme(id: $0.id, name: $0.name, isCustom: false) }
        let files = (try? FileManager.default.contentsOfDirectory(at: customFolder, includingPropertiesForKeys: nil)) ?? []
        let custom = files
            .filter { $0.pathExtension.lowercased() == "css" }
            .map { Theme(id: customPrefix + $0.lastPathComponent, name: $0.deletingPathExtension().lastPathComponent, isCustom: true) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        return builtIn + custom
    }

    /// The theme's CSS, or nil for the default theme and for themes that can't be read
    /// (a missing custom theme falls back to the default rather than failing the render).
    public static func css(for id: String, customFolder: URL = customFolder) -> String? {
        if id == Theme.defaultID { return nil }
        if id.hasPrefix(customPrefix) {
            let name = String(id.dropFirst(customPrefix.count))
            // Only plain file names inside the themes folder.
            guard !name.contains("/"), !name.hasPrefix(".") else { return nil }
            let url = customFolder.appendingPathComponent(name)
            guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= maxCSSBytes else { return nil }
            return try? String(contentsOf: url, encoding: .utf8)
        }
        guard bundled.contains(where: { $0.id == id }),
              let url = Bundle.module.url(forResource: id, withExtension: "css", subdirectory: "themes")
        else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }
}
