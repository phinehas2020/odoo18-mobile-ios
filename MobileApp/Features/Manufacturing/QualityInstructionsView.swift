import SwiftUI
import UIKit

/// Odoo stores instructions as rich HTML, including relative attachment links.
/// Import only text formatting and links; never execute HTML or load embedded assets.
enum QualityInstructionText {
    /// Parses the supported instruction markup directly into SwiftUI text.
    /// No WebKit-backed HTML importer, run-loop pumping, scripts or resource loads.
    static func render(_ source: String, baseURL: URL?) -> AttributedString {
        guard source.range(of: #"<\s*[A-Za-z][^>]*>"#, options: .regularExpression) != nil else {
            return AttributedString(source)
        }
        let tokens = try! NSRegularExpression(pattern: #"(?s)<!--.*?-->|<(?:"[^"]*"|'[^']*'|[^'">])*>|[^<]+|<"#)
        let tags = try! NSRegularExpression(pattern: #"(?is)^<\s*(/?)\s*([a-z][a-z0-9]*)\b(.*)>$"#)
        let hrefs = try! NSRegularExpression(pattern: #"(?is)(?:^|\s)href\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s>]+))"#)
        let blocks: Set<String> = ["p", "div", "li", "ul", "ol", "h1", "h2", "h3", "blockquote", "tr"]
        let ignored: Set<String> = ["script", "style", "iframe", "object", "svg", "head"]
        var suppressed: [String] = []
        var stack: [(tag: String, link: URL?)] = []
        var result = AttributedString()
        var lastCharacter: Character?
        func append(_ value: String, link: URL? = nil) {
            guard !value.isEmpty else { return }
            var run = AttributedString(value)
            var font = Font.body
            if stack.contains(where: { ["b", "strong", "h1", "h2", "h3"].contains($0.tag) }) { font = font.bold() }
            if stack.contains(where: { ["i", "em"].contains($0.tag) }) { font = font.italic() }
            run.font = font
            if let link = link ?? stack.last(where: { $0.link != nil })?.link {
                run.link = link
                run.foregroundColor = .accentColor
                run.underlineStyle = .single
            }
            result.append(run)
            lastCharacter = value.last
        }
        func newline() {
            if lastCharacter != nil && lastCharacter != "\n" { append("\n") }
        }
        let original = source as NSString
        for token in tokens.matches(in: source, range: NSRange(location: 0, length: original.length)) {
            let value = original.substring(with: token.range)
            if value.hasPrefix("<!--") { continue }
            if let tagMatch = tags.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)) {
                let ns = value as NSString
                let closing = ns.substring(with: tagMatch.range(at: 1)) == "/"
                let tag = ns.substring(with: tagMatch.range(at: 2)).lowercased()
                if !suppressed.isEmpty {
                    if closing && suppressed.last == tag { suppressed.removeLast() }
                    else if !closing && ignored.contains(tag) { suppressed.append(tag) }
                    continue
                }
                if ignored.contains(tag) { if !closing { suppressed.append(tag) }; continue }
                if closing {
                    if let index = stack.lastIndex(where: { $0.tag == tag }) { stack.removeSubrange(index...) }
                    if blocks.contains(tag) { newline() }
                    continue
                }
                if tag == "br" { append("\n"); continue }
                if blocks.contains(tag) { newline() }
                if tag == "li" { append("• ") }
                var link: URL?
                if tag == "a" {
                    let attributes = ns.substring(with: tagMatch.range(at: 3))
                    if let match = hrefs.firstMatch(in: attributes, range: NSRange(attributes.startIndex..., in: attributes)),
                       let range = (1...3).map({ match.range(at: $0) }).first(where: { $0.location != NSNotFound }),
                       let url = URL(string: entities((attributes as NSString).substring(with: range)), relativeTo: baseURL)?.absoluteURL,
                       ["http", "https"].contains(url.scheme?.lowercased() ?? "") { link = url }
                }
                if !["img", "hr", "input", "meta", "link", "source"].contains(tag) && !value.hasSuffix("/>") { stack.append((tag, link)) }
            } else if suppressed.isEmpty {
                let text = entities(value).replacingOccurrences(of: #"[\t\r\n ]+"#, with: " ", options: .regularExpression)
                if text == " " && (lastCharacter == nil || lastCharacter == "\n") { continue }
                append(text)
            }
        }
        return result
    }

    private static func entities(_ text: String) -> String {
        let named = ["amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": "\u{00a0}", "ndash": "–", "mdash": "—", "hellip": "…", "copy": "©", "reg": "®"]
        let pattern = try! NSRegularExpression(pattern: #"&(#x[0-9a-fA-F]+|#[0-9]+|[a-zA-Z]+);"#)
        let original = text as NSString
        var output = text
        for match in pattern.matches(in: text, range: NSRange(location: 0, length: original.length)).reversed() {
            let entity = original.substring(with: match.range(at: 1))
            var replacement = named[entity]
            if entity.hasPrefix("#") {
                let hex = entity.hasPrefix("#x")
                if let value = UInt32(entity.dropFirst(hex ? 2 : 1), radix: hex ? 16 : 10), let scalar = UnicodeScalar(value) { replacement = String(scalar) }
            }
            if let replacement, let range = Range(match.range, in: output) { output.replaceSubrange(range, with: replacement) }
        }
        return output
    }
}

struct QualityInstructionsView: View {
    let source: String
    @EnvironmentObject private var config: EnvironmentConfig
    @State private var text = AttributedString()
    @State private var document: InstructionDocument?
    var body: some View {
        Text(text)
            .textSelection(.enabled)
            .lineSpacing(5)
            .padding(.vertical, 6)
            .tint(WorkplaceTheme.accent)
            .frame(maxWidth: .infinity, alignment: .leading)
            .task(id: source) { text = QualityInstructionText.render(source, baseURL: config.baseURL) }
            .environment(\.openURL, OpenURLAction { url in
                guard ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { return .handled }
                if url.host == config.baseURL?.host && url.scheme == config.baseURL?.scheme && url.port == config.baseURL?.port {
                    var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
                    // Use the signed-in Odoo session and preview inline. Do not forward
                    // embedded access tokens into the web-session redirect/logs.
                    let query = components?.queryItems?.filter { !["download", "access_token"].contains($0.name) }
                    components?.queryItems = query
                    document = InstructionDocument(url: components?.url ?? url)
                    return .handled
                }
                return .systemAction
            })
            .fullScreenCover(item: $document) { document in
                NavigationStack {
                    OdooWebView(title: "Instructions", targetURL: document.url.absoluteString)
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                if #available(iOS 26, *) {
                                    Button(role: .close) { self.document = nil }
                                } else {
                                    Button { self.document = nil } label: { Label("Close Instructions", systemImage: "xmark") }
                                        .labelStyle(.iconOnly)
                                }
                            }
                        }
                }
            }
    }
    private struct InstructionDocument: Identifiable {
        let id = UUID()
        let url: URL
    }
}
