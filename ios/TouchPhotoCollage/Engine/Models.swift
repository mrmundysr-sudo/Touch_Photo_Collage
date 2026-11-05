import Foundation

enum ProjectMode: String, CaseIterable { case collage = "COLLAGE", compare = "COMPARE", family = "FAMILY", grid = "GRID" }

/// off: centre crop. smart: keep faces in frame. align: also match face size and height across photos.
enum FaceMode: String, CaseIterable { case off = "OFF", smart = "SMART", align = "ALIGN" }

enum FilterType: String, CaseIterable { case none = "NONE", blackWhite = "BLACK_WHITE", vintage = "VINTAGE", sepia = "SEPIA", fade = "FADE", vivid = "VIVID", cool = "COOL", warm = "WARM" }

enum TextureKind: String, CaseIterable { case paper = "PAPER", linen = "LINEN", dots = "DOTS", stripes = "STRIPES", checker = "CHECKER", grain = "GRAIN" }

enum BackgroundType: String, CaseIterable { case solid = "SOLID", gradient = "GRADIENT", texture = "TEXTURE", transparent = "TRANSPARENT" }

enum FontChoice: String, CaseIterable {
    case sans = "SANS", medium = "MEDIUM", condensed = "CONDENSED", serif = "SERIF", mono = "MONO", script = "SCRIPT", casual = "CASUAL"

    var label: String {
        switch self {
        case .sans: return "Clean"
        case .medium: return "Medium"
        case .condensed: return "Narrow"
        case .serif: return "Serif"
        case .mono: return "Typewriter"
        case .script: return "Script"
        case .casual: return "Casual"
        }
    }
}

enum TextAlign: String, CaseIterable { case left = "LEFT", center = "CENTER", right = "RIGHT" }

/// ARGB colour packed in a UInt32 (0xAARRGGBB), the same representation Android stores (as a signed Int).
typealias ARGB = UInt32

/// A photo imported into private app storage. Dimensions are the raw pixel size, `exif` the EXIF orientation.
struct PhotoRef: Equatable {
    var id: String
    var file: String
    var width: Int
    var height: Int
    var exif: Int = 1
    /// Faces in upright (EXIF-applied) normalised coordinates. nil = not analysed yet, empty = none found.
    var faces: [FRect]? = nil
}

struct Adjustments: Equatable {
    var brightness = 0.0
    var contrast = 0.0
    var saturation = 0.0
    var warmth = 0.0
    var sharpness = 0.0

    var isNeutral: Bool { brightness == 0 && contrast == 0 && saturation == 0 && warmth == 0 && sharpness == 0 }
}

struct CellCaption: Equatable {
    var name = ""
    var relation = ""
    var age = ""

    private static func blank(_ s: String) -> Bool { s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    var isBlank: Bool { Self.blank(name) && Self.blank(relation) && Self.blank(age) }

    func display() -> String {
        let a = age.trimmingCharacters(in: .whitespacesAndNewlines)
        let ageText = a.isEmpty ? "" : (a.first!.isNumber ? "age \(a)" : a)
        return [name.trimmingCharacters(in: .whitespacesAndNewlines), relation.trimmingCharacters(in: .whitespacesAndNewlines), ageText]
            .filter { !$0.isEmpty }.joined(separator: " · ")
    }
}

struct CellEdit: Equatable {
    var photo: PhotoRef? = nil
    /// Crop in display space; see CropMath.
    var zoom = 1.0
    var cx = 0.5
    var cy = 0.5
    /// Clockwise quarter turns.
    var rotation = 0
    var mirror = false
    /// Fit instead of fill: show the whole photo, never crop it.
    var fit = false
    /// The user moved/zoomed this cell by hand, so automatic positioning leaves it alone.
    var manual = false
    var adjustments = Adjustments()
    var filter = FilterType.none
    var caption = CellCaption()
}

struct TextOverlay: Equatable {
    var id: String
    var text: String
    /// Centre of the text, normalised canvas coordinates.
    var x = 0.5
    var y = 0.9
    /// Font size as a fraction of the canvas's shorter side.
    var size = 0.06
    var color: ARGB = 0xFFFFFFFF
    var font = FontChoice.sans
    var bold = false
    var italic = false
    var align = TextAlign.center
    var shadow = true
    /// Optional pill behind the text; 0 = none.
    var backgroundColor: ARGB = 0
    var rotation = 0.0
}

struct CanvasBackground: Equatable {
    var type = BackgroundType.solid
    var color1: ARGB = 0xFFFFFFFF
    var color2: ARGB = 0xFFE9E4DC
    var texture = TextureKind.paper
    var angle = 90.0
}

/// Spacing, margin and corner radius are fractions of the canvas's shorter side so they scale with resolution.
struct CollageStyle: Equatable {
    var spacing = 0.012
    var margin = 0.012
    var cornerRadius = 0.03
    var borderWidth = 0.0
    var borderColor: ARGB = 0xFFFFFFFF
}

struct CollageProject: Equatable {
    static let currentVersion = 1

    var version = CollageProject.currentVersion
    var id: String
    var name = "Untitled collage"
    var createdAt: Int64 = 0
    var updatedAt: Int64 = 0
    var mode = ProjectMode.collage
    var canvas = CanvasSpec.square
    var layout: LayoutTemplate
    var style = CollageStyle()
    var background = CanvasBackground()
    var cells: [CellEdit] = []
    var texts: [TextOverlay] = []
    var faceMode = FaceMode.smart

    var photoCount: Int { cells.filter { $0.photo != nil }.count }
}

/// A reusable look: layout, canvas, spacing and background without any photos.
struct SavedTemplate: Equatable {
    var id: String
    var name: String
    var mode: ProjectMode
    var canvas: CanvasSpec
    var layout: LayoutTemplate
    var style: CollageStyle
    var background: CanvasBackground
}
