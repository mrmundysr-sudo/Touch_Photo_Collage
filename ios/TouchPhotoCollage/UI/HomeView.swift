import SwiftUI
import UIKit

struct HomeView: View {
    let data: HomeData
    let theme: ThemeMode
    let onTheme: (ThemeMode) -> Void
    let onCreate: (ProjectMode) -> Void
    let onOpen: (String) -> Void
    let onDelete: (String) -> Void
    let onTemplate: (SavedTemplate) -> Void
    let onDeleteTemplate: (String) -> Void

    @State private var confirmDelete: ProjectSummary?
    @State private var confirmDeleteTemplate: SavedTemplate?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                Hero { onCreate(.collage) }.padding(.top, 16)
                HStack(spacing: 10) {
                    QuickTile(title: "Side by side", subtitle: "Compare two photos", accent: Palette.teal, icon: .side) { onCreate(.compare) }
                    QuickTile(title: "Family", subtitle: "Resemblance mode", accent: Palette.violet, icon: .faces) { onCreate(.family) }
                    QuickTile(title: "Photo grid", subtitle: "Neat equal tiles", accent: Palette.sunny, icon: .grid) { onCreate(.grid) }
                }
                .padding(.top, 16)

                Text("Recent projects").font(.titleLarge).padding(.top, 24).accessibilityAddTraits(.isHeader)
                if data.recents.isEmpty {
                    EmptyCard(title: "Your collages will appear here", text: "Tap “Create Collage” to make your first one. It takes about ten seconds.").padding(.top, 8)
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(data.recents) { p in
                                RecentCard(summary: p)
                                    .onTapGesture { onOpen(p.id) }
                                    .contextMenu { Button(role: .destructive) { confirmDelete = p } label: { Label("Delete", systemImage: "trash") } }
                                    .accessibilityElement(children: .ignore)
                                    .accessibilityLabel("Open project \(p.name)")
                                    .accessibilityAddTraits(.isButton)
                                    .accessibilityAction(named: "Delete") { confirmDelete = p }
                                    .accessibilityIdentifier("recent-\(p.name)")
                            }
                        }
                        .padding(.vertical, 8)
                    }
                    TinyLabel("Press and hold a project to delete it")
                }

                Text("Saved templates").font(.titleLarge).padding(.top, 24).accessibilityAddTraits(.isHeader)
                if data.templates.isEmpty {
                    EmptyCard(title: "No templates yet", text: "In the editor, choose Layout → Save as template to reuse a look with new photos.").padding(.top, 8)
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(data.templates, id: \.id) { t in
                                TemplateCard(template: t)
                                    .onTapGesture { onTemplate(t) }
                                    .contextMenu { Button(role: .destructive) { confirmDeleteTemplate = t } label: { Label("Delete", systemImage: "trash") } }
                                    .accessibilityElement(children: .ignore)
                                    .accessibilityLabel("Use template \(t.name)")
                                    .accessibilityAddTraits(.isButton)
                                    .accessibilityAction(named: "Delete") { confirmDeleteTemplate = t }
                            }
                        }
                        .padding(.vertical, 8)
                    }
                }

                HStack(spacing: 10) {
                    Image(systemName: "lock.fill").foregroundColor(Palette.primary)
                    Text("Private by design. Everything works offline and your photos never leave this phone unless you save or share.")
                        .font(.bodyMedium).foregroundColor(Palette.onSurfaceVariant)
                }
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 16).fill(Palette.surfaceContainer))
                .padding(.top, 24).padding(.bottom, 24)
            }
            .padding(.horizontal, 16)
        }
        .background(Palette.background.ignoresSafeArea())
        .alert(item: $confirmDelete) { p in
            Alert(
                title: Text("Delete “\(p.name)”?"),
                message: Text("The project and its private photo copies are removed from this app. Your original photos are not touched."),
                primaryButton: .destructive(Text("Delete")) { onDelete(p.id) },
                secondaryButton: .cancel(Text("Keep"))
            )
        }
        .alert("Delete template?", isPresented: Binding(get: { confirmDeleteTemplate != nil }, set: { if !$0 { confirmDeleteTemplate = nil } })) {
            Button("Delete", role: .destructive) { if let t = confirmDeleteTemplate { onDeleteTemplate(t.id) }; confirmDeleteTemplate = nil }
            Button("Keep", role: .cancel) { confirmDeleteTemplate = nil }
        } message: {
            Text(confirmDeleteTemplate.map { "“\($0.name)” will be removed. Projects made from it are not affected." } ?? "")
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 0) {
                Text("Touch").font(.labelLarge).foregroundColor(Palette.primary)
                Text("Photo Collage").font(.headlineLarge).foregroundColor(Palette.onBackground)
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            Spacer()
            Menu {
                Picker("Appearance", selection: Binding(get: { theme }, set: onTheme)) {
                    Text("Match system").tag(ThemeMode.system)
                    Text("Light").tag(ThemeMode.light)
                    Text("Dark").tag(ThemeMode.dark)
                }
            } label: {
                Image(systemName: "gearshape").font(.system(size: 20)).foregroundColor(Palette.onBackground)
                    .frame(width: 48, height: 48).contentShape(Rectangle())
            }
            .accessibilityLabel("Appearance settings")
            .accessibilityIdentifier("appearanceMenu")
        }
        .padding(.top, 12)
    }
}

private struct Hero: View {
    var action: () -> Void
    @State private var pulse = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HeroMosaic().frame(height: 110)
            Text("Turn your photos into one beautiful picture").font(.titleLarge).foregroundColor(.white).padding(.top, 16)
            Text("Pick photos, we arrange them, you save or share.").font(.bodyMedium).foregroundColor(.white.opacity(0.85)).padding(.top, 4)
            Button(action: action) {
                HStack(spacing: 8) {
                    Image(systemName: "plus").font(.system(size: 18, weight: .bold))
                    Text("Create Collage").font(.system(size: 20, weight: .bold))
                }
                .foregroundColor(Color(red: 0x7B / 255, green: 0x2D / 255, blue: 0x1A / 255))
                .frame(maxWidth: .infinity, minHeight: 64)
                .background(RoundedRectangle(cornerRadius: 20).fill(Color.white))
            }
            .buttonStyle(.plain)
            .scaleEffect(pulse ? 1.02 : 1)
            .padding(.top, 16)
            .accessibilityIdentifier("createCollage")
            .accessibilityLabel("Create Collage")
            .accessibilityHint("Choose photos to arrange into a collage")
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 28).fill(LinearGradient(
                colors: [Color(red: 0x3A / 255, green: 0x2A / 255, blue: 0x66 / 255), Color(red: 0x7B / 255, green: 0x3F / 255, blue: 0x8F / 255), Color(red: 0xD9 / 255, green: 0x57 / 255, blue: 0x3C / 255)],
                startPoint: .topLeading, endPoint: .bottomTrailing))
        )
        .onAppear {
            if !UIAccessibility.isReduceMotionEnabled && !UITestSupport.seedPhotos {
                withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) { pulse = true }
            }
        }
    }
}

private struct HeroMosaic: View {
    var body: some View {
        Canvas { ctx, size in
            let colors = [Palette.coral, Palette.sunny, Palette.teal, Palette.violet, Color(red: 0.9, green: 0.42, blue: 0.61)]
            let g = 6.0
            func cell(_ i: Int, _ l: Double, _ t: Double, _ r: Double, _ b: Double) {
                let rect = CGRect(x: l * size.width + g / 2, y: t * size.height + g / 2, width: (r - l) * size.width - g, height: (b - t) * size.height - g)
                ctx.fill(Path(roundedRect: rect, cornerRadius: 12), with: .color(colors[i % colors.count].opacity(0.95)))
            }
            cell(0, 0, 0, 0.34, 1); cell(1, 0.34, 0, 0.68, 0.55); cell(2, 0.34, 0.55, 0.68, 1)
            cell(3, 0.68, 0, 1, 0.4); cell(4, 0.68, 0.4, 1, 1)
        }
        .accessibilityHidden(true)
    }
}

private enum TileIcon { case side, faces, grid }

private struct QuickTile: View {
    var title: String
    var subtitle: String
    var accent: Color
    var icon: TileIcon
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 0) {
                Canvas { ctx, size in
                    switch icon {
                    case .side:
                        ctx.fill(Path(roundedRect: CGRect(x: 0, y: 4, width: size.width / 2 - 2, height: size.height - 8), cornerRadius: 8), with: .color(accent))
                        ctx.fill(Path(roundedRect: CGRect(x: size.width / 2 + 2, y: 4, width: size.width / 2 - 2, height: size.height - 8), cornerRadius: 8), with: .color(accent.opacity(0.6)))
                    case .faces:
                        let rad = size.width * 0.17
                        for (i, pt) in [(0.28, 0.55), (0.72, 0.45)].enumerated() {
                            let c = accent.opacity(i == 0 ? 1 : 0.6)
                            let x = size.width * pt.0, y = size.height * (pt.1 - 0.12)
                            ctx.fill(Path(ellipseIn: CGRect(x: x - rad, y: y - rad, width: rad * 2, height: rad * 2)), with: .color(c))
                            ctx.fill(Path(roundedRect: CGRect(x: x - rad * 1.4, y: size.height * (pt.1 + 0.1), width: rad * 2.8, height: size.height * 0.34), cornerRadius: rad), with: .color(c))
                        }
                    case .grid:
                        let c = size.width / 2 - 2
                        for i in 0..<2 {
                            for j in 0..<2 {
                                ctx.fill(Path(roundedRect: CGRect(x: Double(i) * (c + 4), y: Double(j) * (c + 4), width: c, height: c), cornerRadius: 6), with: .color(accent.opacity((i + j) % 2 == 0 ? 1 : 0.6)))
                            }
                        }
                    }
                }
                .frame(width: 52, height: 52)
                Text(title).font(.labelLarge).lineLimit(1).minimumScaleFactor(0.8).padding(.top, 8)
                Text(subtitle).font(.labelSmall).foregroundColor(Palette.onSurfaceVariant).multilineTextAlignment(.center).lineLimit(2)
            }
            .foregroundColor(Palette.onBackground)
            .frame(maxWidth: .infinity).padding(12)
            .background(RoundedRectangle(cornerRadius: 20).fill(Palette.surfaceContainer))
            .contentShape(RoundedRectangle(cornerRadius: 20))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title). \(subtitle)")
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("tile-\(title)")
    }
}

private struct EmptyCard: View {
    var title: String
    var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.titleMedium)
            Text(text).font(.bodyMedium).foregroundColor(Palette.onSurfaceVariant)
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(18)
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Palette.outlineVariant, lineWidth: 1))
    }
}

private struct RecentCard: View {
    let summary: ProjectSummary
    @State private var image: UIImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack {
                RoundedRectangle(cornerRadius: 16).fill(Palette.surfaceVariant)
                if let image = image {
                    Image(uiImage: image).resizable().scaledToFit().padding(2)
                } else {
                    Image(systemName: "photo").font(.system(size: 28)).foregroundColor(Palette.onSurfaceVariant)
                }
            }
            .frame(width: 140, height: 140).clipShape(RoundedRectangle(cornerRadius: 16))
            Text(summary.name).font(.labelLarge).lineLimit(1).padding(.top, 6)
            TinyLabel("\(summary.photoCount) photo\(summary.photoCount == 1 ? "" : "s")")
        }
        .frame(width: 140)
        .contentShape(Rectangle())
        .task(id: "\(summary.id)-\(summary.updatedAt)") {
            guard let url = summary.thumb else { image = nil; return }
            image = await Task.detached { UIImage(contentsOfFile: url.path) }.value
        }
    }
}

private struct TemplateCard: View {
    let template: SavedTemplate

    var body: some View {
        VStack(spacing: 4) {
            Canvas { ctx, size in
                let a = min(max(template.canvas.aspect, 0.4), 2.5)
                let w = a >= 1 ? size.width : size.height * a
                let h = a >= 1 ? size.width / a : size.height
                let ox = (size.width - w) / 2, oy = (size.height - h) / 2
                for c in template.layout.cells {
                    let r = CGRect(x: ox + c.l * w + 1.5, y: oy + c.t * h + 1.5, width: max(1, c.w * w - 3), height: max(1, c.h * h - 3))
                    ctx.fill(Path(roundedRect: r, cornerRadius: 3), with: .color(Palette.onSurfaceVariant.opacity(0.55)))
                }
            }
            .frame(width: 80, height: 80)
            Text(template.name).font(.labelLarge).lineLimit(1)
            TinyLabel("\(template.layout.count) photos")
        }
        .foregroundColor(Palette.onBackground)
        .frame(width: 110).padding(10)
        .background(RoundedRectangle(cornerRadius: 16).fill(Palette.surfaceContainer))
        .contentShape(Rectangle())
    }
}
