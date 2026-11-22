import Foundation
import JavaScriptCore

public struct RenderOptions: Equatable, Sendable {
    public var localImages: LocalImagePolicy
    /// Render `text/html` outputs that contain scripts as-is and relax the page's CSP.
    /// Off by default: notebooks are untrusted, and Quick Look runs scripts.
    public var allowScripts: Bool

    public init(localImages: LocalImagePolicy = .notebookFolder, allowScripts: Bool = false) {
        self.localImages = localImages
        self.allowScripts = allowScripts
    }

    public init(settings: JuPrevSettings, allowScripts: Bool = false) {
        self.init(localImages: settings.localImagePolicy, allowScripts: allowScripts)
    }
}

public struct RenderedNotebook: Sendable {
    /// A complete, self-contained HTML document.
    public let html: String
    /// The notebook's cells as an HTML fragment (no <head>, styles or CSP).
    public let bodyHTML: String
    /// `metadata.title`, else the first level-1 markdown heading.
    public let title: String?
    public let language: String
    public let cellCount: Int
    /// Outputs that need JavaScript (widgets, Plotly, Bokeh…). With scripts disabled
    /// these show a static fallback or a placeholder.
    public let interactiveOutputs: Int
}

public enum NotebookRenderError: Error, Equatable, LocalizedError {
    case invalidJSON(String)
    case unsupportedFormat(String)
    case rendererFailure(String)

    public var errorDescription: String? {
        switch self {
        case .invalidJSON(let detail): "This file is not a valid Jupyter notebook (\(detail))."
        case .unsupportedFormat(let version): "Notebook format version \(version) is not supported. Only nbformat 4 notebooks can be shown."
        case .rendererFailure(let detail): "The notebook could not be rendered (\(detail))."
        }
    }
}

/// Renders notebooks to static HTML by running the bundled JS renderer in JavaScriptCore.
///
/// Creating a renderer loads the bundle (~25 ms); reuse one for several notebooks.
/// Not thread-safe: use each instance from one thread at a time.
public final class NotebookRenderer {
    private let context: JSContext
    private let renderFunction: JSValue
    private var currentResolver: LocalImageResolver?

    public static let stylesheet: String = loadResource("style", "css")

    /// A styled page explaining why a notebook couldn't be shown.
    public static func errorPage(title: String, message: String) -> String {
        PageTemplate.errorDocument(title: title, message: message)
    }

    public init() throws {
        guard let context = JSContext() else { throw NotebookRenderError.rendererFailure("JavaScriptCore unavailable") }
        self.context = context
        context.evaluateScript(Self.loadResource("render", "js"), withSourceURL: URL(string: "juprev://render.js"))
        if let exception = context.exception {
            throw NotebookRenderError.rendererFailure("bundle failed to load: \(exception)")
        }
        guard let fn = context.objectForKeyedSubscript("NBRender")?.objectForKeyedSubscript("renderNotebook"),
              !fn.isUndefined
        else { throw NotebookRenderError.rendererFailure("renderNotebook missing from bundle") }
        renderFunction = fn

        // Called synchronously from images.js while a render is in progress.
        let resolve: @convention(block) (String) -> String = { [weak self] src in
            let resolution = self?.currentResolver?.resolve(src) ?? .blocked(.disabled)
            switch resolution {
            case .dataURI(let uri): return #"{"src":"\#(uri)"}"#
            case .blocked(let reason): return #"{"blocked":"\#(reason.rawValue)"}"#
            }
        }
        context.setObject(resolve, forKeyedSubscript: "__juprevResolveImage" as NSString)
    }

    public func render(fileURL: URL, options: RenderOptions = RenderOptions()) throws -> RenderedNotebook {
        let data = try Data(contentsOf: fileURL)
        let fallbackTitle = fileURL.deletingPathExtension().lastPathComponent
        return try render(data: data, notebookFolder: fileURL.deletingLastPathComponent(), fallbackTitle: fallbackTitle, options: options)
    }

    /// - Parameter notebookFolder: where relative image paths are resolved from; `nil` disables local images.
    public func render(
        data: Data,
        notebookFolder: URL?,
        fallbackTitle: String? = nil,
        options: RenderOptions = RenderOptions()
    ) throws -> RenderedNotebook {
        guard !data.isEmpty else { throw NotebookRenderError.invalidJSON("the file is empty") }
        guard let json = String(data: data, encoding: .utf8) else {
            throw NotebookRenderError.invalidJSON("not UTF-8 text")
        }
        currentResolver = notebookFolder.map { LocalImageResolver(notebookFolder: $0, policy: options.localImages) }
        defer { currentResolver = nil }

        let optionsJSON = #"{"allowScripts":\#(options.allowScripts)}"#
        context.exception = nil
        let result = renderFunction.call(withArguments: [json, optionsJSON])
        if let exception = context.exception {
            context.exception = nil
            throw Self.error(from: exception)
        }
        guard let resultJSON = result?.toString(),
              let payload = try? JSONDecoder().decode(Payload.self, from: Data(resultJSON.utf8))
        else { throw NotebookRenderError.rendererFailure("unexpected result from renderer") }

        let title = payload.title ?? fallbackTitle
        return RenderedNotebook(
            html: PageTemplate.document(title: title ?? "Notebook", body: payload.html, allowScripts: options.allowScripts),
            bodyHTML: payload.html,
            title: title,
            language: payload.language,
            cellCount: payload.cellCount,
            interactiveOutputs: payload.interactiveOutputs
        )
    }

    private struct Payload: Decodable {
        let html: String
        let title: String?
        let language: String
        let cellCount: Int
        let interactiveOutputs: Int
    }

    private static func error(from exception: JSValue) -> NotebookRenderError {
        let message = exception.objectForKeyedSubscript("message")?.toString() ?? exception.toString() ?? "unknown error"
        switch exception.objectForKeyedSubscript("code")?.toString() {
        case "invalidJSON": return .invalidJSON(message)
        case "unsupportedFormat": return .unsupportedFormat(message)
        default: return .rendererFailure(message)
        }
    }

    private static func loadResource(_ name: String, _ ext: String) -> String {
        guard let url = Bundle.module.url(forResource: name, withExtension: ext),
              let text = try? String(contentsOf: url, encoding: .utf8)
        else { fatalError("NotebookKit resource \(name).\(ext) is missing from the bundle") }
        return text
    }
}
