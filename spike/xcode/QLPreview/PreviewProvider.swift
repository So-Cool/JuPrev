import Foundation
import JavaScriptCore
import QuickLookUI
import UniformTypeIdentifiers
import os

private let logger = Logger(subsystem: "ch.usi.kacper.juprevspike", category: "preview")

final class PreviewProvider: QLPreviewProvider, QLPreviewingController {
    func providePreview(for request: QLFilePreviewRequest) async throws -> QLPreviewReply {
        let home = URL(fileURLWithPath: String(cString: getpwuid(getuid())!.pointee.pw_dir))
        let settings = (try? String(contentsOf: home.appendingPathComponent("Library/Application Support/JuPrevSpike/settings.json"), encoding: .utf8)) ?? "nil"
        logger.notice("settings file = \(settings, privacy: .public)")
        let res = Bundle(for: Self.self)
        let bundleJS = try String(contentsOf: res.url(forResource: "render", withExtension: "js")!, encoding: .utf8)
        let css = try String(contentsOf: res.url(forResource: "style", withExtension: "css")!, encoding: .utf8)
        let text = try String(contentsOf: request.fileURL, encoding: .utf8)

        let t0 = Date()
        let ctx = JSContext()!
        var jsError: String?
        ctx.exceptionHandler = { _, e in jsError = e?.toString() }
        ctx.evaluateScript(bundleJS)
        let out = ctx.objectForKeyedSubscript("NBRender").objectForKeyedSubscript("renderNotebook")
            .call(withArguments: [text])?.toString() ?? "{}"
        let obj = (try? JSONSerialization.jsonObject(with: Data(out.utf8))) as? [String: Any]
        var body = obj?["html"] as? String ?? "<pre>Render failed: \(jsError ?? "unknown")</pre>"
        body = inlineRelativeImages(body, base: request.fileURL.deletingLastPathComponent())
        let ms = Int(Date().timeIntervalSince(t0) * 1000)

        // Probe: does JavaScript execute inside a data-based HTML preview?
        let probe = """
        <div id="probe" style="font:bold 14px sans-serif;padding:6px;background:#fdd">JS DISABLED · render \(ms) ms</div>
        <script>var p=document.getElementById('probe');p.textContent='JS ENABLED · render \(ms) ms';p.style.background='#dfd';</script>
        """
        // Spike variant: files named *nocss* skip the stylesheet to isolate CSS problems.
        let style = request.fileURL.lastPathComponent.contains("nocss") ? "" : css
        let page = "<!doctype html><html><head><meta charset=utf-8><style>\(style)</style></head><body>\(probe)\(body)</body></html>"
        logger.notice("rendered \(request.fileURL.lastPathComponent, privacy: .public) in \(ms) ms, page \(page.utf8.count) bytes, jsError=\(jsError ?? "none", privacy: .public)")
        let dump = FileManager.default.temporaryDirectory.appendingPathComponent("last-preview.html")
        try? page.write(to: dump, atomically: true, encoding: .utf8)
        logger.notice("dumped to \(dump.path, privacy: .public)")
        let reply = QLPreviewReply(dataOfContentType: .html, contentSize: CGSize(width: 900, height: 1100)) { reply in
            reply.stringEncoding = .utf8
            return Data(page.utf8)
        }
        return reply
    }
}

// Spike: can a sandboxed QL extension read images that sit next to the notebook?
private func inlineRelativeImages(_ html: String, base: URL) -> String {
    let re = try! NSRegularExpression(pattern: #"<img src="([^"]+)""#)
    var out = html
    for m in re.matches(in: html, range: NSRange(html.startIndex..., in: html)).reversed() {
        let r = Range(m.range(at: 1), in: html)!
        let src = String(html[r])
        guard !src.hasPrefix("data:"), !src.contains("://") else { continue }
        let url = URL(fileURLWithPath: src.removingPercentEncoding ?? src, relativeTo: base).standardizedFileURL
        do {
            let data = try Data(contentsOf: url)
            logger.notice("read sibling image OK: \(url.path, privacy: .public) (\(data.count) bytes)")
            let mime = url.pathExtension.lowercased() == "svg" ? "image/svg+xml" : "image/\(url.pathExtension.lowercased())"
            out.replaceSubrange(Range(m.range(at: 1), in: out)!, with: "data:\(mime);base64,\(data.base64EncodedString())")
        } catch {
            logger.error("read sibling image FAILED: \(url.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }
    return out
}
