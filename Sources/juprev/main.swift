import Foundation
import NotebookKit

let usage = """
usage: juprev render <notebook.ipynb> [-o <out.html>] [options]

Renders a Jupyter notebook to a self-contained HTML file (stdout by default).

options:
  -o, --output <path>       write HTML to <path>
  --trust-parent-folders    let markdown images use ../ paths outside the notebook's folder
  --no-local-images         don't read any local image files
  --allow-scripts           keep interactive outputs and allow scripts (CSP relaxed)
  --theme <id>              one of: \(Themes.available().map(\.id).joined(separator: ", "))
  --hide-code, --hide-outputs, --hide-stderr
                            hide those parts (as View ▸ Show Code / Outputs / stderr)
  --body-only               print only the cells' HTML fragment
  --time                    print timing to stderr

Anything not set by a flag (theme, shown parts, local and remote images) comes from
the settings file shared with the JuPrev app:
  \(JuPrevSettings.defaultFileURL.path)
"""

func fail(_ message: String, code: Int32 = 1) -> Never {
    FileHandle.standardError.write(Data("juprev: \(message)\n".utf8))
    exit(code)
}

var args = Array(CommandLine.arguments.dropFirst())
guard args.first == "render" else {
    print(usage)
    exit(args.isEmpty || args.first == "-h" || args.first == "--help" ? 0 : 64)
}
args.removeFirst()

var input: String?
var output: String?
var options = RenderOptions(settings: JuPrevSettings.load())
var bodyOnly = false
var showTime = false

while !args.isEmpty {
    let arg = args.removeFirst()
    switch arg {
    case "-o", "--output":
        guard !args.isEmpty else { fail("\(arg) needs a path", code: 64) }
        output = args.removeFirst()
    case "--trust-parent-folders": options.localImages = .trustParentFolders
    case "--no-local-images": options.localImages = .disabled
    case "--allow-scripts": options.allowScripts = true
    case "--hide-code": options.showCode = false
    case "--hide-outputs": options.showOutputs = false
    case "--hide-stderr": options.showStderr = false
    case "--theme":
        guard !args.isEmpty else { fail("--theme needs a theme id", code: 64) }
        let id = args.removeFirst()
        guard Themes.available().contains(where: { $0.id == id }) else {
            fail("unknown theme \(id); available: \(Themes.available().map(\.id).joined(separator: ", "))", code: 64)
        }
        options.themeCSS = Themes.css(for: id)
    case "--body-only": bodyOnly = true
    case "--time": showTime = true
    case "-h", "--help":
        print(usage)
        exit(0)
    default:
        guard !arg.hasPrefix("-"), input == nil else { fail("unexpected argument \(arg)\n\n\(usage)", code: 64) }
        input = arg
    }
}

guard let input else { fail("no notebook given\n\n\(usage)", code: 64) }

do {
    let start = Date()
    let renderer = try NotebookRenderer()
    let loaded = Date()
    let result = try renderer.render(fileURL: URL(fileURLWithPath: input), options: options)
    let done = Date()
    let html = bodyOnly ? result.bodyHTML : result.html

    if let output {
        try Data(html.utf8).write(to: URL(fileURLWithPath: output))
    } else {
        FileHandle.standardOutput.write(Data(html.utf8))
    }
    if showTime {
        let ms = { (a: Date, b: Date) in Int(b.timeIntervalSince(a) * 1000) }
        FileHandle.standardError.write(Data(
            "renderer load \(ms(start, loaded)) ms, render \(ms(loaded, done)) ms, \(result.cellCount) cells, \(result.interactiveOutputs) interactive outputs, \(html.utf8.count / 1024) KB\n".utf8))
    }
} catch {
    fail(error.localizedDescription)
}
