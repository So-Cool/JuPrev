import Foundation

/// Which local image files a notebook's markdown may pull in.
public enum LocalImagePolicy: String, Codable, Sendable {
    /// No local files are read.
    case disabled
    /// Files in the notebook's folder or its subfolders. `..` and symlinks that lead outside are refused.
    case notebookFolder
    /// Relative paths may also climb out of the notebook's folder with `..`, which means
    /// any image on the disk (only absolute paths stay refused).
    case trustParentFolders
}

/// Resolves image references from markdown cells to `data:` URIs.
///
/// The sandbox entitlement lets the process read any path, so this type is where the
/// folder policy is actually enforced. Absolute paths are always refused: notebooks that
/// use them aren't portable, and they would bypass the folder check entirely.
public struct LocalImageResolver: Sendable {
    public enum Resolution: Equatable, Sendable {
        case dataURI(String)
        case blocked(BlockedReason)
    }

    /// Raw values are shared with the JavaScript renderer (images.js).
    public enum BlockedReason: String, Equatable, Sendable {
        case disabled, absolutePath, outsideNotebookFolder, missing, unsupported, tooLarge, unreadable
    }

    public static let maxImageBytes = 25 * 1024 * 1024

    static let mimeTypes: [String: String] = [
        "png": "image/png", "jpg": "image/jpeg", "jpeg": "image/jpeg", "gif": "image/gif",
        "svg": "image/svg+xml", "webp": "image/webp", "bmp": "image/bmp",
    ]

    public let notebookFolder: URL
    public let policy: LocalImagePolicy

    public init(notebookFolder: URL, policy: LocalImagePolicy) {
        self.notebookFolder = notebookFolder
        self.policy = policy
    }

    public func resolve(_ reference: String) -> Resolution {
        guard policy != .disabled else { return .blocked(.disabled) }

        // Markdown links are URL-ish: drop ?query/#fragment, then undo %-escapes.
        var path = reference
        if let cut = path.firstIndex(where: { $0 == "?" || $0 == "#" }) {
            path = String(path[..<cut])
        }
        path = path.removingPercentEncoding ?? path
        guard !path.isEmpty else { return .blocked(.missing) }

        if path.hasPrefix("/") || path.hasPrefix("~") || path.lowercased().hasPrefix("file:") {
            return .blocked(.absolutePath)
        }
        // Any other scheme (http, ftp, …) never reaches the file system.
        if let colon = path.firstIndex(of: ":"), !path[..<colon].contains("/") {
            return .blocked(.unsupported)
        }

        let root = notebookFolder.standardizedFileURL.resolvingSymlinksInPath()
        let target = root.appendingPathComponent(path).standardizedFileURL.resolvingSymlinksInPath()

        if policy == .notebookFolder && !Self.isInside(target, root) {
            return .blocked(.outsideNotebookFolder)
        }
        guard let mime = Self.mimeTypes[target.pathExtension.lowercased()] else {
            return .blocked(.unsupported)
        }

        let values = try? target.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard values?.isRegularFile == true else { return .blocked(.missing) }
        if let size = values?.fileSize, size > Self.maxImageBytes { return .blocked(.tooLarge) }
        guard let data = try? Data(contentsOf: target) else { return .blocked(.unreadable) }
        return .dataURI("data:\(mime);base64,\(data.base64EncodedString())")
    }

    /// Component-wise prefix check, so `/a/bc` is not considered inside `/a/b`.
    static func isInside(_ url: URL, _ folder: URL) -> Bool {
        let child = url.pathComponents
        let parent = folder.pathComponents
        return child.count > parent.count && Array(child.prefix(parent.count)) == parent
    }
}
