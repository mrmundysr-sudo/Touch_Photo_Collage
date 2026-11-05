import UIKit

/// Builds fonts and attributed strings for text overlays and captions.
enum TextStyling {
    static func font(_ choice: FontChoice, size: CGFloat, bold: Bool, italic: Bool) -> UIFont {
        func named(_ regular: String, _ boldName: String?) -> UIFont? {
            UIFont(name: (bold ? boldName : nil) ?? regular, size: size)
        }
        var f: UIFont
        switch choice {
        case .sans:
            f = UIFont.systemFont(ofSize: size, weight: bold ? .bold : .regular)
        case .medium:
            f = UIFont.systemFont(ofSize: size, weight: bold ? .bold : .medium)
        case .condensed:
            f = named("AvenirNextCondensed-Medium", "AvenirNextCondensed-Bold") ?? UIFont.systemFont(ofSize: size, weight: bold ? .bold : .regular)
        case .serif:
            let base = UIFont.systemFont(ofSize: size, weight: bold ? .bold : .regular)
            f = base.fontDescriptor.withDesign(.serif).map { UIFont(descriptor: $0, size: size) } ?? named("Georgia", "Georgia-Bold") ?? base
        case .mono:
            f = named("Menlo-Regular", "Menlo-Bold") ?? UIFont.monospacedSystemFont(ofSize: size, weight: bold ? .bold : .regular)
        case .script:
            f = named("SnellRoundhand", "SnellRoundhand-Bold") ?? UIFont.italicSystemFont(ofSize: size)
        case .casual:
            f = named("MarkerFelt-Thin", "MarkerFelt-Wide") ?? UIFont.systemFont(ofSize: size, weight: bold ? .bold : .regular)
        }
        if italic, let d = f.fontDescriptor.withSymbolicTraits(f.fontDescriptor.symbolicTraits.union(.traitItalic)) {
            f = UIFont(descriptor: d, size: size)
        }
        return f
    }

    static func attributes(for t: TextOverlay, canvasMin: Double) -> [NSAttributedString.Key: Any] {
        let size = CGFloat(max(4, t.size * canvasMin))
        let para = NSMutableParagraphStyle()
        switch t.align {
        case .left: para.alignment = .left
        case .center: para.alignment = .center
        case .right: para.alignment = .right
        }
        var attrs: [NSAttributedString.Key: Any] = [
            .font: font(t.font, size: size, bold: t.bold, italic: t.italic),
            .foregroundColor: CG.uiColor(t.color),
            .paragraphStyle: para,
        ]
        // Fonts without an italic face are slanted so the "Italic" chip always does something.
        if t.italic, let f = attrs[.font] as? UIFont, !f.fontDescriptor.symbolicTraits.contains(.traitItalic) { attrs[.obliqueness] = 0.2 }
        if t.shadow {
            let s = NSShadow()
            s.shadowBlurRadius = size * 0.12
            s.shadowOffset = CGSize(width: 0, height: size * 0.04)
            s.shadowColor = UIColor(white: 0, alpha: 0xAA / 255.0)
            attrs[.shadow] = s
        }
        return attrs
    }

    struct Laid {
        var text: NSAttributedString
        var width: CGFloat
        var height: CGFloat
        var fontSize: CGFloat
    }

    /// Wrapped text no wider than 90% of the canvas, sized to its longest line.
    static func layout(_ t: TextOverlay, canvasW: Double, canvasH: Double) -> Laid {
        let attrs = attributes(for: t, canvasMin: min(canvasW, canvasH))
        let text = t.text.isEmpty ? " " : t.text
        let attributed = NSAttributedString(string: text, attributes: attrs)
        let maxW = max(10, CGFloat(canvasW * 0.9))
        var longest: CGFloat = 1
        for line in text.components(separatedBy: "\n") {
            let wd = NSAttributedString(string: line.isEmpty ? " " : line, attributes: attrs).size().width
            longest = max(longest, ceil(wd))
        }
        let width = min(maxW, longest + 2)
        let box = attributed.boundingRect(with: CGSize(width: width, height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin], context: nil)
        let size = (attrs[.font] as? UIFont)?.pointSize ?? 12
        return Laid(text: attributed, width: width, height: ceil(box.height), fontSize: size)
    }
}
