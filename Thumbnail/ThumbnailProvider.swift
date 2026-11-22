import AppKit
import NotebookKit
import os
import QuickLookThumbnailing

private let logger = Logger(subsystem: "me.kcpr.juprev.thumbnail", category: "thumbnail")

/// Finder thumbnails: a small page with the notebook's title, opening text and first plot.
/// Drawn directly (no web view) so whole folders thumbnail quickly.
final class ThumbnailProvider: QLThumbnailProvider {
    override func provideThumbnail(for request: QLFileThumbnailRequest, _ handler: @escaping (QLThumbnailReply?, Error?) -> Void) {
        do {
            let data = try Data(contentsOf: request.fileURL, options: .mappedIfSafe)
            var summary = try NotebookSummary(data: data)
            if summary.title == nil {
                summary.title = request.fileURL.deletingPathExtension().lastPathComponent
            }
            let image = summary.firstImage.flatMap(NSImage.init(data:))

            // Portrait page, as large as Finder allows.
            let maximum = request.maximumSize
            let height = min(maximum.height, maximum.width / ThumbnailPage.aspect)
            let size = CGSize(width: (height * ThumbnailPage.aspect).rounded(), height: height.rounded())

            let reply = QLThumbnailReply(contextSize: size) {
                ThumbnailPage(summary: summary, image: image).draw(in: CGRect(origin: .zero, size: size))
                return true
            }
            reply.extensionBadge = "ipynb"
            handler(reply, nil)
        } catch {
            logger.error("no thumbnail for \(request.fileURL.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
            handler(nil, error)
        }
    }
}

/// Lays out and draws the thumbnail into the current (unflipped) graphics context.
struct ThumbnailPage {
    static let aspect: CGFloat = 0.78 // roughly A4/Letter

    let summary: NotebookSummary
    let image: NSImage?

    func draw(in rect: CGRect) {
        // Always a light page, like other document thumbnails in Finder.
        NSColor.white.setFill()
        rect.fill()

        let w = rect.width
        let margin = (w * 0.09).rounded()
        let content = rect.insetBy(dx: margin, dy: margin)
        var top = content.maxY // drawing proceeds downwards in unflipped coordinates

        if let title = summary.title {
            let font = NSFont.systemFont(ofSize: w * 0.075, weight: .bold)
            top -= drawText(title, font: font, color: .black, width: content.width, maxLines: 3, x: content.minX, top: top)
            top -= w * 0.035
        }

        // With a plot, keep the text short so the plot gets most of the page.
        let textFont = NSFont.systemFont(ofSize: w * 0.045)
        let maxTextLines = image == nil ? 12 : 4
        let text = summary.lines.joined(separator: " ")
        if !text.isEmpty {
            top -= drawText(text, font: textFont, color: NSColor(white: 0.35, alpha: 1), width: content.width, maxLines: maxTextLines, x: content.minX, top: top)
            top -= w * 0.05
        }

        if let image, image.size.width > 0, image.size.height > 0 {
            let available = CGRect(x: content.minX, y: content.minY, width: content.width, height: max(0, top - content.minY))
            let scale = min(available.width / image.size.width, available.height / image.size.height, 2)
            guard scale > 0 else { return }
            let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
            let frame = CGRect(x: available.minX, y: available.maxY - size.height, width: size.width, height: size.height)
            image.draw(in: frame, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high])
        }
    }

    /// Draws wrapped, truncated text whose first line starts at `top`; returns the height used.
    private func drawText(_ string: String, font: NSFont, color: NSColor, width: CGFloat, maxLines: Int, x: CGFloat, top: CGFloat) -> CGFloat {
        let style = NSMutableParagraphStyle()
        style.lineBreakMode = .byWordWrapping
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color, .paragraphStyle: style]
        let lineHeight = ceil(font.ascender - font.descender + font.leading)
        let maxHeight = lineHeight * CGFloat(maxLines)
        let options: NSString.DrawingOptions = [.usesLineFragmentOrigin, .truncatesLastVisibleLine]
        let measured = (string as NSString).boundingRect(with: CGSize(width: width, height: maxHeight), options: options, attributes: attributes)
        let height = min(ceil(measured.height), maxHeight)
        (string as NSString).draw(with: CGRect(x: x, y: top - height, width: width, height: height), options: options, attributes: attributes)
        return height
    }
}
