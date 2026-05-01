import Foundation
import Markdown

@MainActor
enum HelpRenderer {
    private static var cachedHTML: String?

    static func featuresHTML() -> String {
        if let cached = cachedHTML { return cached }
        let html = renderHTML()
        cachedHTML = html
        return html
    }

    private static func renderHTML() -> String {
        let body: String
        if let url = Bundle.main.url(forResource: "README", withExtension: "md"),
           let text = try? String(contentsOf: url, encoding: .utf8) {
            let features = extractFeatures(from: text)
            let document = Document(parsing: features)
            var visitor = HTMLVisitor()
            body = visitor.visit(document)
        } else {
            body = "<p><em>Could not load help content. View it on <a href=\"https://github.com/DariusCorvus/iqualize#features\">GitHub</a> instead.</em></p>"
        }
        return wrap(body: body)
    }

    /// Returns the slice of the README from `## Features` (inclusive) to the next `## ` heading (exclusive).
    private static func extractFeatures(from markdown: String) -> String {
        var lines: [String] = []
        var inSection = false
        for line in markdown.components(separatedBy: "\n") {
            if line.trimmingCharacters(in: .whitespaces) == "## Features" {
                inSection = true
                lines.append(line)
                continue
            }
            if inSection {
                if line.hasPrefix("## ") { break }
                lines.append(line)
            }
        }
        return lines.joined(separator: "\n")
    }

    private static func wrap(body: String) -> String {
        let header = "<div class=\"help-header\"><a href=\"https://github.com/DariusCorvus/iqualize#features\">View latest on GitHub →</a></div>"
        return """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>\(css)</style>
        </head>
        <body>
        \(header)
        \(body)
        </body>
        </html>
        """
    }

    private static let css = """
    :root { color-scheme: light dark; }
    body {
        font-family: -apple-system, BlinkMacSystemFont, system-ui, sans-serif;
        font-size: 14px;
        line-height: 1.5;
        margin: 0;
        padding: 24px 32px 40px 32px;
        max-width: 760px;
        color: light-dark(#1d1d1f, #f5f5f7);
        background: light-dark(#ffffff, #1e1e1e);
    }
    h2 { font-size: 1.5em; margin-top: 1.4em; border-bottom: 1px solid light-dark(#e5e5e7, #38383a); padding-bottom: 0.2em; }
    h3 { font-size: 1.15em; margin-top: 1.2em; }
    h4 { font-size: 1em; margin-top: 1em; }
    p { margin: 0.6em 0; }
    ul, ol { padding-left: 1.4em; }
    li { margin: 0.2em 0; }
    code {
        font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
        font-size: 0.92em;
        background: light-dark(#f4f4f6, #2a2a2c);
        padding: 0.1em 0.35em;
        border-radius: 4px;
    }
    pre {
        background: light-dark(#f4f4f6, #2a2a2c);
        padding: 12px 14px;
        border-radius: 6px;
        overflow-x: auto;
    }
    pre code { background: transparent; padding: 0; font-size: 0.85em; line-height: 1.4; }
    a { color: light-dark(#0066cc, #4ea1ff); text-decoration: none; }
    a:hover { text-decoration: underline; }
    blockquote {
        margin: 0.8em 0;
        padding: 0 0 0 14px;
        border-left: 3px solid light-dark(#d1d1d6, #48484a);
        color: light-dark(#444, #c7c7cc);
    }
    .help-header {
        font-size: 0.85em;
        opacity: 0.75;
        margin-bottom: 1.2em;
        padding-bottom: 0.6em;
        border-bottom: 1px dashed light-dark(#e5e5e7, #38383a);
    }
    """
}

private struct HTMLVisitor: MarkupVisitor {
    typealias Result = String

    mutating func defaultVisit(_ markup: any Markup) -> String {
        var out = ""
        for child in markup.children { out += visit(child) }
        return out
    }

    mutating func visitDocument(_ document: Document) -> String {
        defaultVisit(document)
    }

    mutating func visitHeading(_ heading: Heading) -> String {
        let level = min(max(heading.level, 1), 6)
        return "<h\(level)>\(visitChildren(of: heading))</h\(level)>\n"
    }

    mutating func visitParagraph(_ paragraph: Paragraph) -> String {
        "<p>\(visitChildren(of: paragraph))</p>\n"
    }

    mutating func visitText(_ text: Text) -> String {
        Self.escapeText(text.string)
    }

    mutating func visitStrong(_ strong: Strong) -> String {
        "<strong>\(visitChildren(of: strong))</strong>"
    }

    mutating func visitEmphasis(_ emphasis: Emphasis) -> String {
        "<em>\(visitChildren(of: emphasis))</em>"
    }

    mutating func visitInlineCode(_ inlineCode: InlineCode) -> String {
        "<code>\(Self.escapeText(inlineCode.code))</code>"
    }

    mutating func visitLink(_ link: Link) -> String {
        let dest = link.destination ?? "#"
        return "<a href=\"\(Self.escapeAttr(dest))\">\(visitChildren(of: link))</a>"
    }

    mutating func visitCodeBlock(_ codeBlock: CodeBlock) -> String {
        let langAttr = codeBlock.language.map { " class=\"language-\(Self.escapeAttr($0))\"" } ?? ""
        return "<pre><code\(langAttr)>\(Self.escapeText(codeBlock.code))</code></pre>\n"
    }

    mutating func visitUnorderedList(_ list: UnorderedList) -> String {
        "<ul>\n\(visitChildren(of: list))</ul>\n"
    }

    mutating func visitOrderedList(_ list: OrderedList) -> String {
        "<ol>\n\(visitChildren(of: list))</ol>\n"
    }

    mutating func visitListItem(_ listItem: ListItem) -> String {
        "<li>\(visitChildren(of: listItem))</li>\n"
    }

    mutating func visitLineBreak(_ lineBreak: LineBreak) -> String { "<br>\n" }
    mutating func visitSoftBreak(_ softBreak: SoftBreak) -> String { " " }
    mutating func visitThematicBreak(_ thematicBreak: ThematicBreak) -> String { "<hr>\n" }

    mutating func visitBlockQuote(_ blockQuote: BlockQuote) -> String {
        "<blockquote>\(visitChildren(of: blockQuote))</blockquote>\n"
    }

    mutating func visitHTMLBlock(_ htmlBlock: HTMLBlock) -> String {
        htmlBlock.rawHTML
    }

    mutating func visitInlineHTML(_ inlineHTML: InlineHTML) -> String {
        inlineHTML.rawHTML
    }

    mutating func visitImage(_ image: Image) -> String {
        let src = image.source ?? ""
        return "<img src=\"\(Self.escapeAttr(src))\" alt=\"\(visitChildren(of: image))\">"
    }

    private mutating func visitChildren(of markup: any Markup) -> String {
        var out = ""
        for child in markup.children { out += visit(child) }
        return out
    }

    private static func escapeText(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
         .replacingOccurrences(of: "<", with: "&lt;")
         .replacingOccurrences(of: ">", with: "&gt;")
    }

    private static func escapeAttr(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
         .replacingOccurrences(of: "\"", with: "&quot;")
         .replacingOccurrences(of: "<", with: "&lt;")
         .replacingOccurrences(of: ">", with: "&gt;")
    }
}
