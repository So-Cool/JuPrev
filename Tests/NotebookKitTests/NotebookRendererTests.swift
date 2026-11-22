import Foundation
import Testing
@testable import NotebookKit

let fixtures = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures")
let snapshots = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("__Snapshots__")

/// Compares against `__Snapshots__/<name>.html`. Record with `JUPREV_RECORD_SNAPSHOTS=1 swift test`.
func assertSnapshot(_ html: String, named name: String, sourceLocation: SourceLocation = #_sourceLocation) throws {
    let url = snapshots.appendingPathComponent("\(name).html")
    if ProcessInfo.processInfo.environment["JUPREV_RECORD_SNAPSHOTS"] != nil {
        try FileManager.default.createDirectory(at: snapshots, withIntermediateDirectories: true)
        try html.write(to: url, atomically: true, encoding: .utf8)
        return
    }
    guard let expected = try? String(contentsOf: url, encoding: .utf8) else {
        Issue.record("Missing snapshot \(name).html — run with JUPREV_RECORD_SNAPSHOTS=1", sourceLocation: sourceLocation)
        return
    }
    #expect(html == expected, "Snapshot \(name).html differs", sourceLocation: sourceLocation)
}

// One renderer for the suite; NotebookRenderer isn't thread-safe, so the suite is serialized.
@Suite(.serialized)
struct NotebookRendererTests {
    static let renderer = try! NotebookRenderer()

    func render(_ name: String, _ options: RenderOptions = RenderOptions()) throws -> RenderedNotebook {
        try Self.renderer.render(fileURL: fixtures.appendingPathComponent(name), options: options)
    }

    // MARK: Snapshots

    @Test func markdownAndMathSnapshot() throws {
        try assertSnapshot(render("markdown-math.ipynb").bodyHTML, named: "markdown-math")
    }

    @Test func outputsSnapshot() throws {
        try assertSnapshot(render("outputs.ipynb").bodyHTML, named: "outputs")
    }

    @Test func imagesSnapshot() throws {
        try assertSnapshot(render("images/nb/images.ipynb").bodyHTML, named: "images")
    }

    // MARK: Markdown and math

    @Test func mathKeepsUnderscoresAndStars() throws {
        let html = try render("markdown-math.ipynb").bodyHTML
        #expect(html.contains(#"<span class="katex">"#))
        #expect(html.contains(#"<span class="katex-display">"#))
        #expect(!html.contains("<em>i"), "underscores inside $…$ must not become emphasis")
        #expect(html.contains(#"<span class="katex-error" title="KaTeX parse error"#), "broken TeX is shown inline")
    }

    @Test func dollarsAndCodeAreNotMath() throws {
        let html = try render("markdown-math.ipynb").bodyHTML
        #expect(html.contains("Prices like $5 and $10 are not math."))
        #expect(html.contains("<code>$x_1$</code>"))
        #expect(html.contains("$$not math$$"))
    }

    @Test func macrosPersistAcrossCellsAndMathJaxIsmsRender() throws {
        let html = try render("markdown-math.ipynb").bodyHTML
        let cell = html.components(separatedBy: "<section").first { $0.contains("Macros from an earlier cell") } ?? ""
        #expect(cell.contains("katex"))
        #expect(!cell.contains("katex-error"))
        #expect(html.components(separatedBy: "katex-error").count == 2, "only the deliberately broken expression fails")
    }

    @Test func titleComesFromFirstHeading() throws {
        #expect(try render("markdown-math.ipynb").title == "Markdown and math")
        #expect(try render("outputs.ipynb").title == "outputs", "falls back to the file name")
    }

    // MARK: Outputs

    @Test func streamsAreMergedAndCarriageReturnsCollapsed() throws {
        let html = try render("outputs.ipynb").bodyHTML
        #expect(html.contains("hello\nworld\n"))
        #expect(html.contains("progress 100%"))
        #expect(!html.contains("progress 10%"))
        #expect(html.contains("warning: &lt;careful&gt;"))
    }

    @Test func ansiTracebacksBecomeSpans() throws {
        let html = try render("outputs.ipynb").bodyHTML
        #expect(html.contains(#"<span class="ansi-red-fg">ZeroDivisionError</span>"#))
        #expect(!html.contains("\u{1B}"))
    }

    @Test func pageLevelTagsAreStrippedFromHTMLOutputs() throws {
        let html = try render("outputs.ipynb").bodyHTML
        #expect(!html.contains("http-equiv=\"refresh\""))
        #expect(html.contains("<table><tr><th>x</th>"))
    }

    @Test func interactiveOutputsUseStaticFallbacksByDefault() throws {
        let result = try render("outputs.ipynb")
        #expect(result.interactiveOutputs == 3)
        #expect(!result.bodyHTML.contains("<script"))
        #expect(!result.bodyHTML.contains("onerror"))
        #expect(result.bodyHTML.contains("Interactive widget"))
        #expect(result.bodyHTML.contains("Interactive output — scripts are disabled"))
    }

    @Test func allowScriptsKeepsInteractiveHTML() throws {
        let result = try render("outputs.ipynb", RenderOptions(allowScripts: true))
        #expect(result.interactiveOutputs == 3)
        #expect(result.bodyHTML.contains("<script>alert(1)</script>"))
        #expect(result.html.contains("script-src 'unsafe-inline'"))
    }

    // MARK: Page

    @Test func staticPagesForbidScriptsAndNetwork() throws {
        let html = try render("outputs.ipynb").html
        #expect(html.contains(#"<meta http-equiv="Content-Security-Policy" content="default-src 'none'; img-src data:; font-src data:; style-src 'unsafe-inline'">"#))
        #expect(!html.contains("script-src"))
        #expect(html.contains("<title>outputs</title>"))
        #expect(html.contains("@font-face"), "KaTeX fonts are inlined")
    }

    // MARK: Images

    @Test func imagePolicyIsApplied() throws {
        let strict = try render("images/nb/images.ipynb").bodyHTML
        #expect(strict.contains(#"data-reason="outsideNotebookFolder" title="../shared/blue.png""#))
        #expect(strict.contains(#"alt="same folder""#))
        #expect(strict.contains(#"width="50" alt="raw tag""#), "raw <img> keeps its other attributes")
        #expect(strict.contains(#"alt="pasted""#), "attachments are inlined")
        #expect(strict.contains(#"data-reason="remote""#))
        #expect(strict.contains(#"data-reason="absolutePath""#))

        let trusting = try render("images/nb/images.ipynb", RenderOptions(localImages: .trustParentFolders)).bodyHTML
        #expect(trusting.contains(#"alt="parent""#))
        #expect(!trusting.contains("outsideNotebookFolder"))

        let none = try render("images/nb/images.ipynb", RenderOptions(localImages: .disabled)).bodyHTML
        #expect(none.contains(#"data-reason="disabled" title="img/red.png""#))
        #expect(none.contains(#"alt="pasted""#), "attachments live inside the notebook, so they still load")
    }

    @Test func noNotebookFolderMeansNoLocalImages() throws {
        let data = try Data(contentsOf: fixtures.appendingPathComponent("images/nb/images.ipynb"))
        let html = try Self.renderer.render(data: data, notebookFolder: nil).bodyHTML
        #expect(html.contains(#"data-reason="disabled""#))
    }

    // MARK: Errors

    @Test func rejectsOldNotebookFormat() {
        #expect(throws: NotebookRenderError.unsupportedFormat("3")) { try render("v3.ipynb") }
    }

    @Test func rejectsInvalidJSON() {
        #expect {
            try render("broken.ipynb")
        } throws: { error in
            if case .invalidJSON = error as? NotebookRenderError { return true }
            return false
        }
        #expect(throws: NotebookRenderError.self) {
            try Self.renderer.render(data: Data([0xFF, 0xFE]), notebookFolder: nil)
        }
        #expect(throws: NotebookRenderError.invalidJSON("the file is empty")) {
            try Self.renderer.render(data: Data(), notebookFolder: nil)
        }
    }

    @Test func rendererRecoversAfterAnError() throws {
        _ = try? render("broken.ipynb")
        #expect(try render("outputs.ipynb").cellCount == 10)
    }
}

struct SettingsTests {
    @Test func roundTripsAndToleratesBadFiles() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("juprev-settings-\(UUID().uuidString)/settings.json")
        #expect(JuPrevSettings.load(from: url) == JuPrevSettings(), "missing file gives defaults")

        try JuPrevSettings(trustParentFolders: true).save(to: url)
        #expect(JuPrevSettings.load(from: url).trustParentFolders)
        #expect(JuPrevSettings.load(from: url).localImagePolicy == .trustParentFolders)

        try Data(#"{"trustParentFolders": true, "fromTheFuture": 1}"#.utf8).write(to: url)
        #expect(JuPrevSettings.load(from: url).trustParentFolders, "unknown keys are ignored")

        try Data("not json".utf8).write(to: url)
        #expect(JuPrevSettings.load(from: url) == JuPrevSettings())
    }

    @Test func defaultFileIsInTheRealHomeFolder() {
        let path = JuPrevSettings.defaultFileURL.path
        #expect(path.hasSuffix("/Library/Application Support/JuPrev/settings.json"))
        #expect(!path.contains("/Library/Containers/"))
    }
}
