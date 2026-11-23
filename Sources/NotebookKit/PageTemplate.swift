import Foundation

/// Wraps rendered cells in a self-contained HTML document.
enum PageTemplate {
    /// Static pages may load nothing: no scripts, no network, no frames.
    /// Everything they need (images, fonts) is inlined as `data:` URIs.
    /// `base-uri` and `form-action` aren't covered by `default-src`; without them a stray
    /// <base> or <form> could retarget links or submissions.
    static let staticCSP = "default-src 'none'; img-src data:; font-src data:; style-src 'unsafe-inline'; base-uri 'none'; form-action 'none'"
    static let staticRemoteImagesCSP = "default-src 'none'; img-src data: https:; font-src data:; style-src 'unsafe-inline'; base-uri 'none'; form-action 'none'"

    /// With scripts allowed, outputs typically pull libraries (Plotly, Bokeh…) from CDNs.
    /// Frames too: some outputs render in an iframe (Folium maps, Plotly's iframe renderer).
    static let scriptsCSP = "default-src 'none'; img-src data: blob: https:; font-src data: https:; style-src 'unsafe-inline' https:; script-src 'unsafe-inline' 'unsafe-eval' https:; connect-src https:; frame-src data: blob: https:; base-uri 'none'; form-action 'none'"

    static func csp(for options: RenderOptions) -> String {
        options.allowScripts ? scriptsCSP : options.remoteImages ? staticRemoteImagesCSP : staticCSP
    }

    /// Classes on <html> that hide parts of the notebook (see notebook.css).
    static func htmlClasses(for options: RenderOptions) -> String {
        [
            options.showCode ? nil : "hide-code",
            options.showOutputs ? nil : "hide-outputs",
            options.showStderr ? nil : "hide-stderr",
        ].compactMap { $0 }.joined(separator: " ")
    }

    static func document(title: String, body: String, options: RenderOptions) -> String {
        """
        <!doctype html>
        <html class="\(htmlClasses(for: options))">
        <head>
        <meta charset="utf-8">
        <meta http-equiv="Content-Security-Policy" content="\(csp(for: options))">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <meta name="color-scheme" content="light dark">
        <title>\(escape(title))</title>
        <style>\(NotebookRenderer.stylesheet)</style>\(options.themeCSS.map { "\n<style id=\"theme\">\($0)</style>" } ?? "")
        </head>
        <body>
        <main class="notebook">
        \(body)
        </main>
        </body>
        </html>
        """
    }

    static func errorDocument(title: String, message: String, themeCSS: String?) -> String {
        document(
            title: title,
            body: """
            <div class="render-error">
            <h1>\(escape(title))</h1>
            <p>\(escape(message))</p>
            </div>
            """,
            options: RenderOptions(themeCSS: themeCSS)
        )
    }

    static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
