import Foundation

/// What a Finder thumbnail shows: the title, some opening text and the first plot.
/// Parsed straight from the JSON — no JavaScript renderer, so it's cheap enough for
/// thumbnailing whole folders.
public struct NotebookSummary: Equatable, Sendable {
    public var title: String?
    /// Plain-text lines from the first markdown cells (after the title), markup stripped.
    public var lines: [String]
    /// The first PNG/JPEG/GIF output, decoded. (SVG is skipped: NSImage mangles
    /// matplotlib's clip paths into black shapes.)
    public var firstImage: Data?
    public var cellCount: Int

    public init(title: String? = nil, lines: [String] = [], firstImage: Data? = nil, cellCount: Int = 0) {
        self.title = title
        self.lines = lines
        self.firstImage = firstImage
        self.cellCount = cellCount
    }

    public init(data: Data, maxLines: Int = 6) throws {
        guard let nb = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let cells = nb["cells"] as? [[String: Any]]
        else { throw NotebookRenderError.invalidJSON("no cells") }

        self.init(cellCount: cells.count)
        if let metaTitle = (nb["metadata"] as? [String: Any])?["title"] as? String, !metaTitle.isEmpty {
            title = metaTitle
        }

        for cell in cells {
            if lines.count >= maxLines && firstImage != nil { break }
            switch cell["cell_type"] as? String {
            case "markdown" where lines.count < maxLines:
                // Whole blocks first: their contents span lines and aren't prose.
                var source = Self.text(cell["source"])
                for block in [
                    #"(?is)<(script|style)\b.*?</\1\s*>"#,             // scripts and styles
                    #"(?s)\$\$.*?\$\$|\\\[.*?\\\]"#,                 // display math
                    #"(?s)\\begin\{([a-zA-Z*]+)\}.*?\\end\{\1\}"#,  // LaTeX environments
                    #"(?s)```.*?```|~~~.*?~~~"#,                        // fenced code
                ] {
                    source = source.replacingOccurrences(of: block, with: "", options: .regularExpression)
                }
                for line in source.components(separatedBy: .newlines) {
                    if title == nil, let heading = Self.heading(line) {
                        title = heading
                        continue
                    }
                    let plain = Self.plainText(line)
                    if !plain.isEmpty && lines.count < maxLines { lines.append(plain) }
                }
            case "code" where firstImage == nil:
                firstImage = Self.firstImage(in: cell["outputs"] as? [[String: Any]] ?? [])
            default:
                break
            }
        }
    }

    static func text(_ source: Any?) -> String {
        (source as? [String])?.joined() ?? source as? String ?? ""
    }

    static func heading(_ line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        // CommonMark: 1–6 hashes followed by a space (so "#hashtag" is plain text).
        guard trimmed.range(of: #"^#{1,6}(\s|$)"#, options: .regularExpression) != nil else { return nil }
        // "# Title #" closing hashes are optional ATX syntax.
        let text = trimmed.drop { $0 == "#" }
            .replacingOccurrences(of: #"\s+#+\s*$"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        return text.isEmpty ? nil : plainText(text)
    }

    /// Strips the markdown/HTML that would look like noise in a tiny thumbnail.
    /// Inline math keeps its TeX (minus the `$`), so `_` and `*` inside it survive.
    static func plainText(_ line: String) -> String {
        var math: [String] = []
        // Escaped dollars are literal; \(…\) is inline math like $…$.
        var s = line.replacingOccurrences(of: #"\$"#, with: "\u{E002}")
            .replacingMatches(of: #"\$([^$]+)\$|\\\((.+?)\\\)"#) { groups in
                math.append(groups[1].isEmpty ? groups[2] : groups[1])
                return "\u{E000}\(math.count - 1)\u{E001}"
            }
        let replacements: [(String, String)] = [
            (#"^\s*\([^)]*\)=\s*$"#, ""),             // MyST targets: (label)=
            (#"(\{[\w:-]+\}|:[\w-]+:)`[^`]*`"#, ""),     // roles: {cite}`x`, :label:`x`
            (#"<(?:[^>"']|"[^"]*"|'[^']*')*>"#, ""),  // HTML tags, even with ">" in quoted attributes
            (#"!\[[^\]]*\]\([^)]*\)"#, ""),          // images
            (#"\[([^\]]*)\]\([^)]*\)"#, "$1"),       // links -> text
            (#"^\s{0,3}(#+|>|[-*+]|\d+\.)\s+"#, ""), // heading/quote/list markers
            (#"\*+|`+|~~"#, ""),                       // emphasis, code
            (#"(?<![A-Za-z0-9])_+|_+(?![A-Za-z0-9])"#, ""), // _emphasis_, but not snake_case
            (#"^\s*(---+|\*\*\*+|___+|\|.*\|)\s*$"#, ""), // rules, table rows
        ]
        for (pattern, template) in replacements {
            s = s.replacingOccurrences(of: pattern, with: template, options: .regularExpression)
        }
        s = s.replacingMatches(of: "\u{E000}(\\d+)\u{E001}") { math[Int($0[1])!] }
            .replacingOccurrences(of: "\u{E002}", with: "$")
        return s.trimmingCharacters(in: .whitespaces)
    }

    static func firstImage(in outputs: [[String: Any]]) -> Data? {
        for output in outputs {
            guard let bundle = output["data"] as? [String: Any] else { continue }
            for mime in ["image/png", "image/jpeg", "image/gif"] {
                let base64 = text(bundle[mime]).filter { !$0.isWhitespace }
                if !base64.isEmpty, let data = Data(base64Encoded: base64) { return data }
            }
        }
        return nil
    }
}

private extension String {
    /// Regex replace with a closure receiving the match's capture groups (0 = whole match).
    func replacingMatches(of pattern: String, with transform: ([String]) -> String) -> String {
        let regex = try! NSRegularExpression(pattern: pattern)
        var result = ""
        var last = startIndex
        for match in regex.matches(in: self, range: NSRange(startIndex..., in: self)) {
            let range = Range(match.range, in: self)!
            let groups = (0..<match.numberOfRanges).map { i in
                Range(match.range(at: i), in: self).map { String(self[$0]) } ?? ""
            }
            result += self[last..<range.lowerBound] + transform(groups)
            last = range.upperBound
        }
        return result + self[last...]
    }
}
