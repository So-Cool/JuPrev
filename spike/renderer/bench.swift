// Spike benchmark: render notebooks with the JS bundle inside JavaScriptCore.
// Usage: swift bench.swift <out-dir> <notebook>...
import Foundation
import JavaScriptCore

let args = CommandLine.arguments
let outDir = URL(fileURLWithPath: args[1])
let here = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
let bundle = try String(contentsOf: here.appendingPathComponent("dist/render.js"), encoding: .utf8)
let css = try String(contentsOf: here.appendingPathComponent("dist/style.css"), encoding: .utf8)

var t0 = Date()
let ctx = JSContext()!
ctx.exceptionHandler = { _, e in print("JS exception:", e?.toString() ?? "?") }
ctx.evaluateScript(bundle)
let render = ctx.objectForKeyedSubscript("NBRender").objectForKeyedSubscript("renderNotebook")!
print(String(format: "context + bundle load: %.0f ms", Date().timeIntervalSince(t0) * 1000))

for path in args.dropFirst(2) {
    let url = URL(fileURLWithPath: path)
    let text = try String(contentsOf: url, encoding: .utf8)
    t0 = Date()
    guard let result = render.call(withArguments: [text])?.toString(),
          let data = result.data(using: .utf8),
          let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
          let html = obj["html"] as? String else { print("FAILED", path); continue }
    let ms = Date().timeIntervalSince(t0) * 1000
    let page = "<!doctype html><meta charset=utf-8><style>\(css)</style><body>\(html)</body>"
    let out = outDir.appendingPathComponent(url.deletingPathExtension().lastPathComponent + ".html")
    try page.write(to: out, atomically: true, encoding: .utf8)
    print(String(format: "%7.0f ms  in %6.1f MB  out %6.1f MB  interactive=%@  %@",
                 ms, Double(text.utf8.count) / 1e6, Double(page.utf8.count) / 1e6,
                 "\(obj["interactiveCount"]!)", url.lastPathComponent))
}
