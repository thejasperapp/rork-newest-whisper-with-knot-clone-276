import SwiftUI
import UIKit

/// Native, non-executing reply formatting. Code is always literal text;
/// unsupported or unfinished syntax stays readable, including during streaming.
struct WhisperEmberRichText: View {
    let text: String
    var onDark = false
    var baseSize: CGFloat = 15
    var inkOverride: Color? = nil
    var expandsHorizontally = true
    private var ink: Color { inkOverride ?? (onDark ? .white : WhisperEmberSheetTheme.ink) }
    private var soft: Color { ink.opacity(onDark ? 0.72 : 0.68) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(Self.blocks(from: text).enumerated()), id: \.offset) { _, block in
                blockView(block)
            }
        }
        .frame(maxWidth: expandsHorizontally ? .infinity : nil, alignment: .leading)
    }

    @ViewBuilder private func blockView(_ block: RichBlock) -> some View {
        switch block {
        case .heading(let string, let level):
            formatted(string)
                .font(.system(size: baseSize + (level == 1 ? 6 : level == 2 ? 4 : 2), weight: .bold))
                .padding(.top, 5)
        case .bullet(let string):
            listRow(marker: "•", string: string)
        case .nestedBullet(let string, let depth):
            listRow(marker: "•", string: string).padding(.leading, CGFloat(depth) * 16)
        case .numbered(let number, let string):
            listRow(marker: "\(number).", string: string)
        case .quote(let string):
            HStack(alignment: .top, spacing: 10) {
                RoundedRectangle(cornerRadius: 2).fill(soft.opacity(0.6)).frame(width: 3)
                formatted(string).font(.system(size: baseSize).italic()).foregroundStyle(soft)
            }.fixedSize(horizontal: false, vertical: true).padding(.vertical, 4)
        case .code(let language, let code):
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(language.isEmpty ? "Code" : language).font(.caption.weight(.medium)).foregroundStyle(soft)
                    Spacer(minLength: 16)
                    Button {
                        UIPasteboard.general.string = code
                        Haptics.tap()
                    } label: { Label("Copy", systemImage: "doc.on.doc").font(.caption) }
                        .buttonStyle(.plain).foregroundStyle(ink)
                        .accessibilityLabel("Copy code")
                }
                ScrollView(.horizontal) {
                    Text(verbatim: code).font(.system(size: max(12, baseSize - 2), design: .monospaced))
                        .foregroundStyle(ink).textSelection(.enabled).fixedSize(horizontal: true, vertical: true)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(ink.opacity(0.065), in: .rect(cornerRadius: 12))
            .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(ink.opacity(0.12), lineWidth: 0.5) }
        case .divider:
            Rectangle().fill(ink.opacity(0.16)).frame(height: 1).padding(.vertical, 5)
        case .paragraph(let string):
            formatted(string).font(.system(size: baseSize)).lineSpacing(3)
        case .paragraphBreak:
            Color.clear.frame(height: 3).accessibilityHidden(true)
        }
    }

    private func listRow(marker: String, string: String) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Text(marker).font(.system(size: baseSize, weight: .medium).monospacedDigit())
                .foregroundStyle(soft).frame(minWidth: 10, alignment: .trailing)
            formatted(string).font(.system(size: baseSize)).lineSpacing(3)
        }
    }

    private func formatted(_ string: String) -> some View {
        Text(styledInline(string)).foregroundStyle(ink).fixedSize(horizontal: false, vertical: true)
    }

    /// Explicit narrow extensions, not arbitrary HTML rendering. Inline code is
    /// protected so examples of the formatting syntax remain literal.
    private func styledInline(_ string: String) -> AttributedString {
        guard let expression = try? NSRegularExpression(pattern: #"`+[^`\n]*`+|==([^=\n]+)==|<small>([\s\S]*?)</small>"#) else { return Self.inline(string) }
        let source = string as NSString
        var result = AttributedString(), position = 0
        for match in expression.matches(in: string, range: NSRange(location: 0, length: source.length)) {
            if match.range.location > position {
                result.append(Self.inline(source.substring(with: NSRange(location: position, length: match.range.location - position))))
            }
            if match.range(at: 1).location != NSNotFound {
                var span = Self.inline(source.substring(with: match.range(at: 1)))
                span.foregroundColor = onDark ? .yellow : Color(red: 0.48, green: 0.28, blue: 0)
                span.backgroundColor = Color.yellow.opacity(onDark ? 0.18 : 0.3)
                result.append(span)
            } else if match.range(at: 2).location != NSNotFound {
                var span = Self.inline(source.substring(with: match.range(at: 2)))
                span.foregroundColor = soft
                span.font = .system(size: max(12, baseSize - 1), weight: .light)
                result.append(span)
            } else { result.append(Self.inline(source.substring(with: match.range))) }
            position = NSMaxRange(match.range)
        }
        if position < source.length { result.append(Self.inline(source.substring(from: position))) }
        return result
    }

    nonisolated enum RichBlock: Hashable {
        case heading(String, level: Int)
        case bullet(String)
        case nestedBullet(String, depth: Int)
        case numbered(Int, String)
        case paragraph(String)
        case quote(String)
        case code(language: String, content: String)
        case divider
        case paragraphBreak
    }

    nonisolated static func blocks(from text: String) -> [RichBlock] {
        let lines = text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        var out: [RichBlock] = [], code: [String] = [], fence: Character?, fenceCount = 0, language = ""
        for rawLine in lines {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if let activeFence = fence {
                if line.first == activeFence && line.prefix(while: { $0 == activeFence }).count >= fenceCount && line.allSatisfy({ $0 == activeFence }) {
                    out.append(.code(language: language, content: code.joined(separator: "\n")))
                    code = []; fence = nil
                } else { code.append(rawLine) }
                continue
            }
            if let first = line.first, first == "`" || first == "~" {
                let count = line.prefix(while: { $0 == first }).count
                if count >= 3 {
                    fence = first; fenceCount = count; language = String(line.dropFirst(count)).trimmingCharacters(in: .whitespaces)
                    continue
                }
            }
            if line.isEmpty {
                if !out.isEmpty, out.last != .paragraphBreak { out.append(.paragraphBreak) }
                continue
            }
            if ["---", "***", "___"].contains(line) { out.append(.divider); continue }
            let hashes = line.prefix(while: { $0 == "#" }).count
            if (1...6).contains(hashes), line.dropFirst(hashes).first == " " {
                out.append(.heading(String(line.dropFirst(hashes + 1)), level: hashes)); continue
            }
            if line.hasPrefix(">") { out.append(.quote(String(line.dropFirst()).trimmingCharacters(in: .whitespaces))); continue }
            if line.hasPrefix("- ") || line.hasPrefix("• ") || line.hasPrefix("* ") || line.hasPrefix("+ ") {
                let indentation = rawLine.prefix(while: { $0 == " " || $0 == "\t" }).reduce(0) { $0 + ($1 == "\t" ? 4 : 1) }
                let content = String(line.dropFirst(2))
                out.append(indentation >= 2 ? .nestedBullet(content, depth: min(6, indentation / 2)) : .bullet(content)); continue
            }
            if let range = line.range(of: #"^\d{1,9}[.)]\s+"#, options: .regularExpression) {
                let digits = line.prefix(while: { $0.isNumber })
                out.append(.numbered(Int(digits) ?? 1, String(line[range.upperBound...]))); continue
            }
            out.append(.paragraph(line))
        }
        // A partial streamed fence remains a code box rather than turning code
        // into Markdown or losing the unfinished response.
        if fence != nil { out.append(.code(language: language, content: code.joined(separator: "\n"))) }
        while out.last == .paragraphBreak { out.removeLast() }
        return out
    }

    nonisolated static func inline(_ string: String) -> AttributedString {
        (try? AttributedString(markdown: string, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(string)
    }

    nonisolated static func plainText(_ text: String) -> String {
        blocks(from: text).map { block in
            switch block {
            case .code(_, let content): return content
            case .divider: return "—"
            case .paragraphBreak: return ""
            case .bullet(let value), .nestedBullet(let value, _): return "• " + plainInline(value)
            case .numbered(let number, let value): return "\(number). " + plainInline(value)
            case .quote(let value): return "> " + plainInline(value)
            case .heading(let value, _), .paragraph(let value): return plainInline(value)
            }
        }.joined(separator: "\n")
    }

    nonisolated private static func plainInline(_ string: String) -> String {
        // Protect literal inline code when stripping our presentation markers.
        guard let expression = try? NSRegularExpression(pattern: #"`+[^`\n]*`+|==([^=\n]+)==|<small>([\s\S]*?)</small>"#) else { return String(inline(string).characters) }
        let source = string as NSString
        var value = "", position = 0
        for match in expression.matches(in: string, range: NSRange(location: 0, length: source.length)) {
            if match.range.location > position {
                value += String(inline(source.substring(with: NSRange(location: position, length: match.range.location - position))).characters)
            }
            let range = match.range(at: 1).location != NSNotFound ? match.range(at: 1) : match.range(at: 2).location != NSNotFound ? match.range(at: 2) : match.range
            value += String(inline(source.substring(with: range)).characters)
            position = NSMaxRange(match.range)
        }
        if position < source.length { value += String(inline(source.substring(from: position)).characters) }
        return value
    }
}
