package com.mundymorning.collage.engine.project

import com.mundymorning.collage.engine.layout.CanvasSpec
import com.mundymorning.collage.engine.layout.LayoutTemplate
import com.mundymorning.collage.engine.model.FRect

enum class ProjectMode { COLLAGE, COMPARE, FAMILY, GRID }

/** OFF: centre crop. SMART: keep faces in frame. ALIGN: also match face size and height across photos. */
enum class FaceMode { OFF, SMART, ALIGN }

enum class FilterType { NONE, BLACK_WHITE, VINTAGE, SEPIA, FADE, VIVID, COOL, WARM }

enum class TextureKind { PAPER, LINEN, DOTS, STRIPES, CHECKER, GRAIN }

enum class BackgroundType { SOLID, GRADIENT, TEXTURE, TRANSPARENT }

enum class FontChoice(val family: String, val label: String) {
    SANS("sans-serif", "Clean"),
    MEDIUM("sans-serif-medium", "Medium"),
    CONDENSED("sans-serif-condensed", "Narrow"),
    SERIF("serif", "Serif"),
    MONO("monospace", "Typewriter"),
    SCRIPT("cursive", "Script"),
    CASUAL("casual", "Casual"),
}

enum class TextAlign { LEFT, CENTER, RIGHT }

/** A photo imported into private app storage. Dimensions are the raw pixel size, [exif] the EXIF orientation. */
data class PhotoRef(
    val id: String,
    val file: String,
    val width: Int,
    val height: Int,
    val exif: Int = 1,
    /** Faces in upright (EXIF-applied) normalised coordinates. null = not analysed yet, empty = none found. */
    val faces: List<FRect>? = null,
)

data class Adjustments(
    val brightness: Float = 0f,
    val contrast: Float = 0f,
    val saturation: Float = 0f,
    val warmth: Float = 0f,
    val sharpness: Float = 0f,
) {
    val isNeutral: Boolean get() = brightness == 0f && contrast == 0f && saturation == 0f && warmth == 0f && sharpness == 0f
}

data class CellCaption(val name: String = "", val relation: String = "", val age: String = "") {
    val isBlank: Boolean get() = name.isBlank() && relation.isBlank() && age.isBlank()

    fun display(): String = listOf(
        name.trim(),
        relation.trim(),
        age.trim().let { if (it.isEmpty()) "" else if (it.firstOrNull()?.isDigit() == true) "age $it" else it },
    ).filter { it.isNotEmpty() }.joinToString(" · ")
}

data class CellEdit(
    val photo: PhotoRef? = null,
    /** Crop in display space; see CropMath. */
    val zoom: Float = 1f,
    val cx: Float = 0.5f,
    val cy: Float = 0.5f,
    /** Clockwise quarter turns. */
    val rotation: Int = 0,
    val mirror: Boolean = false,
    /** Fit instead of fill: show the whole photo, never crop it. */
    val fit: Boolean = false,
    /** The user moved/zoomed this cell by hand, so automatic positioning leaves it alone. */
    val manual: Boolean = false,
    val adjustments: Adjustments = Adjustments(),
    val filter: FilterType = FilterType.NONE,
    val caption: CellCaption = CellCaption(),
)

data class TextOverlay(
    val id: String,
    val text: String,
    /** Centre of the text, normalised canvas coordinates. */
    val x: Float = 0.5f,
    val y: Float = 0.9f,
    /** Font size as a fraction of the canvas's shorter side. */
    val size: Float = 0.06f,
    val color: Int = 0xFFFFFFFF.toInt(),
    val font: FontChoice = FontChoice.SANS,
    val bold: Boolean = false,
    val italic: Boolean = false,
    val align: TextAlign = TextAlign.CENTER,
    val shadow: Boolean = true,
    /** Optional pill behind the text; 0 = none. */
    val backgroundColor: Int = 0,
    val rotation: Float = 0f,
)

data class Background(
    val type: BackgroundType = BackgroundType.SOLID,
    val color1: Int = 0xFFFFFFFF.toInt(),
    val color2: Int = 0xFFE9E4DC.toInt(),
    val texture: TextureKind = TextureKind.PAPER,
    val angle: Float = 90f,
)

/** Spacing, margin and corner radius are fractions of the canvas's shorter side so they scale with resolution. */
data class CollageStyle(
    val spacing: Float = 0.012f,
    val margin: Float = 0.012f,
    val cornerRadius: Float = 0.03f,
    val borderWidth: Float = 0f,
    val borderColor: Int = 0xFFFFFFFF.toInt(),
)

data class CollageProject(
    val version: Int = CURRENT_VERSION,
    val id: String,
    val name: String = "Untitled collage",
    val createdAt: Long = 0L,
    val updatedAt: Long = 0L,
    val mode: ProjectMode = ProjectMode.COLLAGE,
    val canvas: CanvasSpec = CanvasSpec.SQUARE,
    val layout: LayoutTemplate,
    val style: CollageStyle = CollageStyle(),
    val background: Background = Background(),
    val cells: List<CellEdit> = emptyList(),
    val texts: List<TextOverlay> = emptyList(),
    val faceMode: FaceMode = FaceMode.SMART,
) {
    val photoCount: Int get() = cells.count { it.photo != null }

    companion object {
        const val CURRENT_VERSION = 1
    }
}

/** A reusable look: layout, canvas, spacing and background without any photos. */
data class SavedTemplate(
    val id: String,
    val name: String,
    val mode: ProjectMode,
    val canvas: CanvasSpec,
    val layout: LayoutTemplate,
    val style: CollageStyle,
    val background: Background,
)
