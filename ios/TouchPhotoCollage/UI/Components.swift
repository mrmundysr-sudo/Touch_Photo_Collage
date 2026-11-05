import SwiftUI
import UIKit

struct SectionLabel: View {
    var text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text).font(.labelMedium).foregroundColor(Palette.onSurfaceVariant).padding(.bottom, 2)
            .accessibilityAddTraits(.isHeader)
    }
}

struct TinyLabel: View {
    var text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text).font(.labelSmall).foregroundColor(Palette.onSurfaceVariant).fixedSize(horizontal: false, vertical: true)
    }
}

/// Slider with a label and value, at least 44pt tall.
struct LabeledSlider: View {
    var label: String
    var value: Double
    var range: ClosedRange<Double>
    var onChange: (Double) -> Void
    var onDone: () -> Void
    var valueText: (Double) -> String = { "\(Int(($0 * 100).rounded()))" }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(label).font(.labelLarge)
                Spacer()
                Text(valueText(value)).font(.labelMedium).foregroundColor(Palette.onSurfaceVariant)
            }
            Slider(
                value: Binding(get: { min(max(value, range.lowerBound), range.upperBound) }, set: { onChange($0) }),
                in: range, onEditingChanged: { editing in if !editing { onDone() } }
            )
            .tint(Palette.primary)
            .frame(minHeight: 32)
            .accessibilityLabel(label)
            .accessibilityValue(valueText(value))
        }
    }
}

struct ChipRow<Content: View>: View {
    var spacing: CGFloat = 8
    @ViewBuilder var content: () -> Content

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: spacing) { content() }.padding(.vertical, 2)
        }
    }
}

struct SelectChip: View {
    var label: String
    var selected: Bool
    var action: () -> Void

    init(_ label: String, _ selected: Bool, action: @escaping () -> Void) {
        self.label = label; self.selected = selected; self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if selected { Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)) }
                Text(label).font(.labelLarge).lineLimit(1)
            }
            .padding(.horizontal, 14).frame(minHeight: 36)
            .foregroundColor(selected ? Palette.onSecondaryContainer : Palette.onBackground)
            .background(Capsule().fill(selected ? Palette.secondaryContainer : Color.clear))
            .overlay(Capsule().stroke(selected ? Color.clear : Palette.outlineVariant, lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .frame(minHeight: 44)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

struct ToolChip: View {
    var symbol: String
    var label: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: symbol).font(.system(size: 14, weight: .semibold))
                Text(label).font(.labelLarge).lineLimit(1)
            }
            .padding(.horizontal, 12).frame(minHeight: 36)
            .foregroundColor(Palette.onBackground)
            .background(Capsule().fill(Palette.surfaceContainerHigh))
            .overlay(Capsule().stroke(Palette.outlineVariant, lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .frame(minHeight: 44)
        .accessibilityLabel(label)
    }
}

struct FilledButton: ButtonStyle {
    var prominent = true
    @Environment(\.isEnabled) private var enabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.titleMedium)
            .frame(maxWidth: .infinity, minHeight: 52)
            .foregroundColor(prominent ? Palette.onPrimary : Palette.primary)
            .background(RoundedRectangle(cornerRadius: 16).fill(prominent ? Palette.primary : Color.clear))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(prominent ? Color.clear : Palette.outline, lineWidth: 1))
            .opacity(configuration.isPressed ? 0.8 : (enabled ? 1 : 0.4))
    }
}

let swatchColors: [ARGB] = [
    0xFFFFFFFF, 0xFFF5EFE6, 0xFFE9DCC9, 0xFF1C1B1F, 0xFF424242, 0xFFE8613C, 0xFFFFC857, 0xFF3FA796, 0xFF4A90D9,
    0xFF7B6CF0, 0xFFE46A9B, 0xFF9BCB6B, 0xFFB5651D, 0xFFCFD8DC,
]

struct ColorSwatches: View {
    var selected: ARGB?
    var onPick: (ARGB) -> Void
    @State private var custom = false

    var body: some View {
        ChipRow {
            ForEach(swatchColors, id: \.self) { c in
                let sel = selected == c
                Button { onPick(c) } label: {
                    Circle().fill(Color(CG.uiColor(c))).frame(width: 36, height: 36)
                        .overlay(Circle().stroke(sel ? Palette.primary : Palette.outlineVariant, lineWidth: sel ? 3 : 1))
                        .frame(width: 44, height: 44).contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(String(format: "Colour #%06X", c & 0xFFFFFF))
                .accessibilityAddTraits(sel ? .isSelected : [])
            }
            Button { custom = true } label: {
                Circle().stroke(Palette.outline, lineWidth: 1).frame(width: 36, height: 36)
                    .overlay(Text("+").font(.titleMedium).foregroundColor(Palette.onBackground))
                    .frame(width: 44, height: 44).contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Custom colour")
        }
        .sheet(isPresented: $custom) {
            CustomColorSheet(initial: selected ?? 0xFFFFFFFF) { onPick($0); custom = false } onCancel: { custom = false }
        }
    }
}

struct CustomColorSheet: View {
    var initial: ARGB
    var onPick: (ARGB) -> Void
    var onCancel: () -> Void
    @State private var h = 0.0
    @State private var s = 0.0
    @State private var v = 1.0

    private var color: UIColor { UIColor(hue: CGFloat(h / 360), saturation: CGFloat(s), brightness: CGFloat(v), alpha: 1) }

    var body: some View {
        VStack(spacing: 12) {
            Text("Custom colour").font(.titleLarge)
            RoundedRectangle(cornerRadius: 12).fill(Color(color)).frame(height: 48)
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Palette.outlineVariant, lineWidth: 1))
            LabeledSlider(label: "Hue", value: h, range: 0...360, onChange: { h = $0 }, onDone: {}, valueText: { "\(Int($0))°" })
            LabeledSlider(label: "Richness", value: s, range: 0...1, onChange: { s = $0 }, onDone: {})
            LabeledSlider(label: "Brightness", value: v, range: 0...1, onChange: { v = $0 }, onDone: {})
            HStack {
                Button("Cancel", action: onCancel).buttonStyle(FilledButton(prominent: false))
                Button("Use colour") {
                    var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
                    color.getRed(&r, green: &g, blue: &b, alpha: &a)
                    let argb = 0xFF00_0000 | (UInt32((r * 255).rounded()) << 16) | (UInt32((g * 255).rounded()) << 8) | UInt32((b * 255).rounded())
                    onPick(argb)
                }.buttonStyle(FilledButton())
            }
            Spacer(minLength: 0)
        }
        .padding(20)
        .background(Palette.background.ignoresSafeArea())
        .presentationDetents([.height(400)])
        .onAppear {
            var hh: CGFloat = 0, ss: CGFloat = 0, bb: CGFloat = 0, aa: CGFloat = 0
            UIColor(argb: initial).getHue(&hh, saturation: &ss, brightness: &bb, alpha: &aa)
            h = Double(hh) * 360; s = Double(ss); v = Double(bb)
        }
    }
}

/// Mini diagram of a layout.
struct LayoutThumb: View {
    var layout: LayoutTemplate
    var aspect: Double
    var selected: Bool
    var label: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Canvas { ctx, size in
                    let a = min(max(aspect, 0.4), 2.5)
                    let w = a >= 1 ? size.width : size.height * a
                    let h = a >= 1 ? size.width / a : size.height
                    let ox = (size.width - w) / 2, oy = (size.height - h) / 2
                    let gap = 1.6
                    for c in layout.cells {
                        let r = CGRect(x: ox + c.l * w + gap, y: oy + c.t * h + gap, width: max(1, c.w * w - 2 * gap), height: max(1, c.h * h - 2 * gap))
                        ctx.fill(Path(roundedRect: r, cornerRadius: 2), with: .color(selected ? Palette.primary : Palette.onSurfaceVariant.opacity(0.55)))
                    }
                }
                .frame(width: 44, height: 44)
                .frame(width: 56, height: 56)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(selected ? Palette.primary : Palette.outlineVariant, lineWidth: selected ? 2 : 1))
                if !label.isEmpty {
                    Text(label).font(.labelSmall).foregroundColor(Palette.onSurfaceVariant).lineLimit(1)
                }
            }
            .frame(width: 72).padding(4).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Layout \(label)")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
