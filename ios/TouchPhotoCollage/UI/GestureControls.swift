import SwiftUI
import UIKit

/// Isolated so that per-frame zoom changes re-evaluate only this tiny view, never the bar or the editor.
struct ZoomReadout: View {
    @ObservedObject var live: LiveGesture
    var cell: Int
    var committedZoom: Double

    var body: some View {
        let z = (live.active && live.index == cell) ? live.zoom : committedZoom
        Text(String(format: "×%.1f", z)).font(.labelLarge).monospacedDigit()
            .accessibilityIdentifier("zoomReadout")
            .accessibilityLabel(String(format: "Zoom %.1f times", z))
    }
}

struct ModeBadge: View {
    @ObservedObject var live: LiveGesture
    var mode: TouchMode
    var cell: Int
    var committedZoom: Double

    var body: some View {
        let z = (live.active && live.index == cell) ? live.zoom : committedZoom
        Text("\(mode.glyph) \(mode.label)  ×\(String(format: "%.1f", z))")
            .font(.labelLarge).monospacedDigit()
            .padding(.horizontal, 12).padding(.vertical, 6)
            .foregroundColor(Palette.onPrimary)
            .background(Capsule().fill(Palette.primary))
            .accessibilityHidden(true)
    }
}

/// The Touch Gesture Standard control strip: PAN and ZOOM mode buttons, RESET, and a banner that always states what one
/// finger does. Every target is at least 56pt high.
struct GestureModeBar: View {
    var mode: TouchMode
    var onModeChange: (TouchMode) -> Void
    var onReset: () -> Void
    var hasTarget: Bool
    var onHelp: () -> Void
    var zoomLabel: AnyView?

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                ForEach([TouchMode.pan, TouchMode.zoom], id: \.self) { m in
                    let sel = m == mode
                    Button { onModeChange(m) } label: {
                        ModeLabel(symbol: m == .pan ? "arrow.up.and.down.and.arrow.left.and.right" : "arrow.up.and.down", label: m.label)
                            .frame(maxWidth: .infinity, minHeight: 56)
                            .foregroundColor(sel ? Palette.onPrimary : Palette.primary)
                            .background(RoundedRectangle(cornerRadius: 16).fill(sel ? Palette.primary : Color.clear))
                            .overlay(RoundedRectangle(cornerRadius: 16).stroke(sel ? Color.clear : Palette.outline, lineWidth: 1))
                            .contentShape(RoundedRectangle(cornerRadius: 16))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier(m == .pan ? "modePan" : "modeZoom")
                    .accessibilityLabel(m == .pan ? "Pan mode" : "Zoom mode")
                    .accessibilityHint(m == .pan ? "One finger drags the selected photo." : "One finger slides up to zoom in and down to zoom out.")
                    .accessibilityAddTraits(sel ? .isSelected : [])
                }
                Button(action: onReset) {
                    ModeLabel(symbol: "arrow.counterclockwise", label: "RESET")
                        .frame(maxWidth: .infinity, minHeight: 56)
                        .foregroundColor(Palette.primary)
                        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Palette.outline, lineWidth: 1))
                        .contentShape(RoundedRectangle(cornerRadius: 16))
                }
                .buttonStyle(.plain)
                .disabled(!hasTarget)
                .opacity(hasTarget ? 1 : 0.4)
                .accessibilityIdentifier("resetPhoto")
                .accessibilityLabel("Reset")
                .accessibilityHint("Reset the selected photo to its automatic position and zoom")
                Button(action: onHelp) {
                    Text("?").font(.system(size: 22, weight: .bold)).foregroundColor(Palette.primary)
                        .frame(width: 56, height: 56).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("touchHelp")
                .accessibilityLabel("How the touch controls work")
            }
            HStack {
                Text(mode.instruction(hasTarget: hasTarget)).font(.system(size: 14, weight: .semibold))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("modeBanner")
                Spacer(minLength: 4)
                if hasTarget, let z = zoomLabel { z }
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading) // room for two lines, so switching modes never resizes the canvas
            .foregroundColor(hasTarget ? Palette.onPrimaryContainer : Palette.onSurfaceVariant)
            .background(RoundedRectangle(cornerRadius: 12).fill(hasTarget ? Palette.primaryContainer : Palette.surfaceVariant))
        }
        .padding(.horizontal, 12)
    }
}

private struct ModeLabel: View {
    var symbol: String
    var label: String

    var body: some View {
        VStack(spacing: 2) {
            Image(systemName: symbol).font(.system(size: 18, weight: .semibold))
            Text(label).font(.system(size: 13, weight: .bold)).lineLimit(1).minimumScaleFactor(0.8)
        }
    }
}

/// First-use explanation plus the touch preferences: pinch, zoom sensitivity and the optional frame-timing readout.
struct GestureIntroSheet: View {
    var pinchEnabled: Bool
    var onPinchChange: (Bool) -> Void
    var sensitivity: Double
    var onSensitivityChange: (Double) -> Void
    var frameTiming: Bool
    var onFrameTimingChange: (Bool) -> Void
    var onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Move and zoom with one finger").font(.titleLarge)
                    Text("1. Tap a photo to choose it.")
                    Text("2. Pick PAN or ZOOM under the picture. The bar always tells you what your finger will do.")
                    Text("3. PAN: drag one finger anywhere to move the photo.")
                    Text("4. ZOOM: slide one finger up to zoom in, down to zoom out. Tiny movements make tiny changes.")
                    Text("5. RESET puts the photo back where the app first placed it.")
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Zoom sensitivity: \(String(format: "%.1f", sensitivity))×").font(.system(size: 15, weight: .semibold))
                        Slider(
                            value: Binding(get: { OneFingerMath.sliderFromSensitivity(sensitivity) }, set: { onSensitivityChange(OneFingerMath.sensitivityFromSlider($0)) }),
                            in: 0...1
                        )
                        .tint(Palette.primary).frame(minHeight: 44)
                        .accessibilityLabel("Zoom sensitivity").accessibilityValue(String(format: "%.1f times", sensitivity))
                        HStack(spacing: 8) {
                            Button("Fine") { onSensitivityChange(OneFingerMath.sensitivityFine) }.buttonStyle(FilledButton(prominent: false))
                            Button("Normal") { onSensitivityChange(OneFingerMath.sensitivityDefault) }.buttonStyle(FilledButton(prominent: false))
                            Button("Fast") { onSensitivityChange(2) }.buttonStyle(FilledButton(prominent: false))
                        }
                        Text("Lower is finer: more finger travel for the same zoom.").font(.system(size: 12))
                    }
                    Toggle(isOn: Binding(get: { pinchEnabled }, set: onPinchChange)) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Also allow two-finger pinch").font(.system(size: 15, weight: .semibold))
                            Text("Optional. You can change this any time with the ? button.").font(.system(size: 12))
                        }
                    }
                    .tint(Palette.primary).accessibilityIdentifier("pinchToggle")
                    Toggle(isOn: Binding(get: { frameTiming }, set: onFrameTimingChange)) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Show frame timing").font(.system(size: 15, weight: .semibold))
                            Text("For testing smoothness: shows fps and slowest frame.").font(.system(size: 12))
                        }
                    }
                    .tint(Palette.primary)
                }
                .padding(20)
                .foregroundColor(Palette.onBackground)
            }
            Button("Got it", action: onDismiss).buttonStyle(FilledButton())
                .padding(.horizontal, 20).padding(.bottom, 16).accessibilityIdentifier("gotIt")
        }
        .background(Palette.background.ignoresSafeArea())
    }
}

/// Small overlay showing display-synchronised frame timing, to measure real-device smoothness. Only shown when the user
/// enabled it: the display link runs every vsync while visible.
struct FrameTimingOverlay: View {
    @StateObject private var meter = FrameMeter()

    var body: some View {
        Text(meter.text).font(.system(size: 11, design: .monospaced)).foregroundColor(.white)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.7)))
            .onAppear { meter.start() }
            .onDisappear { meter.stop() }
            .accessibilityIdentifier("frameTiming")
    }
}

final class FrameMeter: ObservableObject {
    @Published var text = "frames: …"
    private let stats = FrameStats()
    private var link: CADisplayLink?
    private var shown: Int64 = 0

    func start() {
        guard link == nil else { return }
        let l = CADisplayLink(target: self, selector: #selector(tick(_:)))
        l.add(to: .main, forMode: .common)
        link = l
    }

    func stop() { link?.invalidate(); link = nil; stats.reset() }

    @objc private func tick(_ l: CADisplayLink) {
        let now = Int64(l.timestamp * 1e9)
        stats.record(now)
        if now - shown > 400_000_000 { shown = now; text = stats.summary() }
    }

    deinit { link?.invalidate() }
}
