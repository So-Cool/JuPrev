import Foundation

/// Preferences shared by the app and the Quick Look extension.
///
/// They live in a plain JSON file rather than an App Group: with ad-hoc signing, App Group
/// access makes macOS 15 ask "would like to access data from other apps" (see README.md#design-notes).
/// The app writes the file through a read-write sandbox exception for its folder; the
/// extension reads it through its read-only exception.
public struct JuPrevSettings: Codable, Equatable, Sendable {
    /// Let markdown images use `..` to reach files above the notebook's folder.
    public var trustParentFolders = false
    /// Load `https://` images in the app. Quick Look never loads anything from the network.
    public var loadRemoteImages = false

    public init(trustParentFolders: Bool = false, loadRemoteImages: Bool = false) {
        self.trustParentFolders = trustParentFolders
        self.loadRemoteImages = loadRemoteImages
    }

    public var localImagePolicy: LocalImagePolicy {
        trustParentFolders ? .trustParentFolders : .notebookFolder
    }

    /// `~/Library/Application Support/JuPrev/settings.json`, using the real home folder
    /// (inside the sandbox `NSHomeDirectory()` points at the app's container).
    public static var defaultFileURL: URL {
        realHomeDirectory.appendingPathComponent("Library/Application Support/JuPrev/settings.json")
    }

    static var realHomeDirectory: URL {
        if let entry = getpwuid(getuid()), let dir = entry.pointee.pw_dir {
            return URL(fileURLWithPath: String(cString: dir), isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
    }

    /// Missing or unreadable files give the defaults; settings must never block a preview.
    public static func load(from url: URL = defaultFileURL) -> JuPrevSettings {
        guard let data = try? Data(contentsOf: url),
              let settings = try? JSONDecoder().decode(JuPrevSettings.self, from: data)
        else { return JuPrevSettings() }
        return settings
    }

    public func save(to url: URL = defaultFileURL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(self).write(to: url, options: .atomic)
    }

    // Decode field by field so files written by newer versions (extra keys) or older ones
    // (missing keys) still load.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        trustParentFolders = try c.decodeIfPresent(Bool.self, forKey: .trustParentFolders) ?? false
        loadRemoteImages = try c.decodeIfPresent(Bool.self, forKey: .loadRemoteImages) ?? false
    }
}
