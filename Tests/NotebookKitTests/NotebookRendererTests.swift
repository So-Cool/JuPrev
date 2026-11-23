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

    @Test func headingsGetJupyterIdsAndFormTheOutline() throws {
        let nb = #"""
        {"nbformat": 4, "metadata": {}, "cells": [
          {"cell_type": "markdown", "metadata": {}, "source": "# Intro\n## The $\\alpha$ parameter\n## Intro"},
          {"cell_type": "code", "metadata": {}, "source": "", "outputs": [
            {"output_type": "display_data", "data": {"text/markdown": "# Not in outline"}}]}
        ]}
        """#
        let result = try Self.renderer.render(data: Data(nb.utf8), notebookFolder: nil)
        #expect(result.headings == [
            NotebookHeading(level: 1, text: "Intro", id: "Intro"),
            NotebookHeading(level: 2, text: #"The \alpha parameter"#, id: #"The-\alpha-parameter"#),
            NotebookHeading(level: 2, text: "Intro", id: "Intro-1"),
        ])
        #expect(result.bodyHTML.contains(#"<h1 id="Intro">"#))
        #expect(result.bodyHTML.contains(#"<h1 id="Not-in-outline">"#), "output headings get ids but stay out of the outline")
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

    @Test func hiddenPartsAreClassesOnTheRoot() throws {
        #expect(try render("outputs.ipynb").html.contains(#"<html class="">"#))
        let hidden = try render("outputs.ipynb", RenderOptions(showCode: false, showOutputs: false)).html
        #expect(hidden.contains(#"<html class="hide-code hide-outputs">"#))
        #expect(NotebookRenderer.stylesheet.contains("html.hide-code .cell.code .input"))
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

    @Test func remoteImagesAreOptIn() throws {
        let off = try render("images/nb/images.ipynb")
        #expect(off.bodyHTML.contains(#"data-reason="remote""#))
        #expect(!off.html.contains("img-src data: https:"))

        let on = try render("images/nb/images.ipynb", RenderOptions(remoteImages: true))
        #expect(on.bodyHTML.contains(#"<img src="https://example.com/x.png" alt="remote">"#))
        #expect(on.html.contains("img-src data: https:"))
        #expect(!on.html.contains("script-src"))
    }

    @Test func imageSourcesAreEscaped() throws {
        let nb = #"""
        {"nbformat": 4, "nbformat_minor": 5, "metadata": {}, "cells": [
          {"cell_type": "markdown", "metadata": {}, "source": "![a](attachment:x.png) ![b](https://e.com/a\"onerror=\"x.png)",
           "attachments": {"x.png": {"image/png\" onerror=\"alert(1)": "AAAA"}}}
        ]}
        """#
        let html = try Self.renderer.render(data: Data(nb.utf8), notebookFolder: nil, options: RenderOptions(remoteImages: true)).bodyHTML
        #expect(!html.contains(#"" onerror=""#))
        #expect(!html.contains(#""onerror=""#))
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
        #expect(!JuPrevSettings.load(from: url).loadRemoteImages)
        #expect(JuPrevSettings.load(from: url).showCode, "missing keys keep their defaults")
        #expect(JuPrevSettings.load(from: url).localImagePolicy == .trustParentFolders)

        try JuPrevSettings(showCode: false).save(to: url)
        #expect(RenderOptions(settings: .load(from: url)).showCode == false)
        #expect(RenderOptions(settings: .load(from: url), showCode: true).showCode, "a window's choice wins")

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

struct NotebookSummaryTests {
    func summary(_ name: String) throws -> NotebookSummary {
        try NotebookSummary(data: Data(contentsOf: fixtures.appendingPathComponent(name)))
    }

    @Test func takesTitleAndPlainTextFromMarkdown() throws {
        let s = try summary("markdown-math.ipynb")
        #expect(s.title == "Markdown and math")
        #expect(s.lines.first == "Inline a_i * b_i and x_{1}^2 keep their underscores and stars.")
        #expect(s.lines.count == 6)
        #expect(!s.lines.contains { $0.contains("](") || $0.contains("<") })
        #expect(s.cellCount == 9)
    }

    @Test func findsFirstImageOutput() throws {
        let s = try summary("outputs.ipynb")
        #expect(s.title == nil)
        let png = try #require(s.firstImage)
        #expect(png.prefix(4) == Data([0x89, 0x50, 0x4E, 0x47]))
    }

    @Test func svgOutputsAreSkipped() throws {
        let nb = #"{"nbformat": 4, "metadata": {}, "cells": [{"cell_type": "code", "outputs": [{"output_type": "display_data", "data": {"image/svg+xml": "<svg/>"}}]}]}"#
        #expect(try NotebookSummary(data: Data(nb.utf8)).firstImage == nil)
    }

    @Test func displayMathAndCodeBlocksAreDropped() throws {
        let s = try summary("markdown-math.ipynb")
        let text = s.lines.joined(separator: " ")
        #expect(!text.contains("\\sum") && !text.contains("begin{align}") && !text.contains("not math$$"))
        #expect(text.contains("Display:"))
    }

    @Test func scriptsAndAttributesDontLeakIntoText() throws {
        let s = try summary("csp-probe.ipynb")
        #expect(s.title == "CSP probe")
        #expect(!s.lines.contains { $0.contains("SCRIPT RAN:") || $0.contains("insertAdjacentHTML") || $0.contains("width=") })
    }

    @Test func rejectsNonNotebooks() {
        #expect(throws: (any Error).self) { try NotebookSummary(data: Data("[1, 2]".utf8)) }
        #expect(throws: (any Error).self) { try NotebookSummary(data: Data()) }
    }

    @Test func plainTextStripsMarkup() {
        #expect(NotebookSummary.plainText("- see [the docs](https://x.y) and **bold** `code`") == "see the docs and bold code")
        #expect(NotebookSummary.plainText("| a | b |") == "")
        #expect(NotebookSummary.plainText("![img](a.png)") == "")
        #expect(NotebookSummary.plainText("_emphasis_ keeps snake_case") == "emphasis keeps snake_case")
        #expect(NotebookSummary.plainText(#"Prices like \$5 and \$10, and \(\alpha_1\)"#) == #"Prices like $5 and $10, and \alpha_1"#)
        #expect(NotebookSummary.plainText("(text:meta-explainers:tabular)=") == "")
        #expect(NotebookSummary.plainText(":label:`sec_intro` See {cite}`smith` here") == "See  here")
    }

    @Test func headingsDropClosingHashes() {
        #expect(NotebookSummary.heading("# Explanation Generation #") == "Explanation Generation")
        #expect(NotebookSummary.heading("## C# tips") == "C# tips")
        #expect(NotebookSummary.heading("#hashtag") == nil)
        #expect(NotebookSummary.heading("plain") == nil)
    }
}
