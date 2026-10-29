package com.mundymorning.collage.engine.project

import com.mundymorning.collage.engine.layout.CanvasSpec
import com.mundymorning.collage.engine.layout.LayoutTemplate
import com.mundymorning.collage.engine.model.FRect
import org.json.JSONArray
import org.json.JSONObject

/**
 * Versioned JSON (de)serialisation of projects and templates. Unknown / missing fields fall back to defaults so
 * old files keep opening after the format grows.
 */
object ProjectJson {

    // ---- encode ----

    private fun FRect.toJson() = JSONArray().put(l.toDouble()).put(t.toDouble()).put(r.toDouble()).put(b.toDouble())

    private fun JSONArray.toRect() = FRect(
        getDouble(0).toFloat(), getDouble(1).toFloat(), getDouble(2).toFloat(), getDouble(3).toFloat(),
    )

    private fun PhotoRef.toJson() = JSONObject()
        .put("id", id).put("file", file).put("w", width).put("h", height).put("exif", exif)
        .also { o -> faces?.let { f -> o.put("faces", JSONArray().also { a -> f.forEach { r -> a.put(r.toJson()) } }) } }

    private fun Adjustments.toJson() = JSONObject()
        .put("brightness", brightness.toDouble()).put("contrast", contrast.toDouble())
        .put("saturation", saturation.toDouble()).put("warmth", warmth.toDouble()).put("sharpness", sharpness.toDouble())

    private fun CellEdit.toJson() = JSONObject().apply {
        photo?.let { put("photo", it.toJson()) }
        put("zoom", zoom.toDouble()); put("cx", cx.toDouble()); put("cy", cy.toDouble())
        put("rotation", rotation); put("mirror", mirror); put("fit", fit); put("manual", manual)
        put("adjust", adjustments.toJson()); put("filter", filter.name)
        put("caption", JSONObject().put("name", caption.name).put("relation", caption.relation).put("age", caption.age))
    }

    private fun TextOverlay.toJson() = JSONObject()
        .put("id", id).put("text", text).put("x", x.toDouble()).put("y", y.toDouble()).put("size", size.toDouble())
        .put("color", color).put("font", font.name).put("bold", bold).put("italic", italic).put("align", align.name)
        .put("shadow", shadow).put("bg", backgroundColor).put("rot", rotation.toDouble())

    private fun Background.toJson() = JSONObject()
        .put("type", type.name).put("c1", color1).put("c2", color2).put("texture", texture.name).put("angle", angle.toDouble())

    private fun CollageStyle.toJson() = JSONObject()
        .put("spacing", spacing.toDouble()).put("margin", margin.toDouble()).put("radius", cornerRadius.toDouble())
        .put("border", borderWidth.toDouble()).put("borderColor", borderColor)

    private fun CanvasSpec.toJson() = JSONObject().put("w", ratioW).put("h", ratioH).put("label", label)

    private fun LayoutTemplate.toJson() = JSONObject().put("id", id).put("name", name)
        .put("cells", JSONArray().also { a -> cells.forEach { a.put(it.toJson()) } })

    fun toJson(p: CollageProject): JSONObject = JSONObject()
        .put("version", p.version).put("id", p.id).put("name", p.name)
        .put("createdAt", p.createdAt).put("updatedAt", p.updatedAt)
        .put("mode", p.mode.name).put("canvas", p.canvas.toJson()).put("layout", p.layout.toJson())
        .put("style", p.style.toJson()).put("background", p.background.toJson())
        .put("cells", JSONArray().also { a -> p.cells.forEach { a.put(it.toJson()) } })
        .put("texts", JSONArray().also { a -> p.texts.forEach { a.put(it.toJson()) } })
        .put("faceMode", p.faceMode.name)

    fun serialize(p: CollageProject): String = toJson(p).toString()

    fun toJson(t: SavedTemplate): JSONObject = JSONObject()
        .put("id", t.id).put("name", t.name).put("mode", t.mode.name).put("canvas", t.canvas.toJson())
        .put("layout", t.layout.toJson()).put("style", t.style.toJson()).put("background", t.background.toJson())

    // ---- decode ----

    // Static lookup (no reflection) so R8/ProGuard in release builds can never strip what it needs.
    private inline fun <reified E : Enum<E>> enumOf(name: String?, default: E): E =
        enumValues<E>().firstOrNull { it.name == name } ?: default

    private fun JSONObject.f(key: String, def: Float) = optDouble(key, def.toDouble()).toFloat()

    private fun readPhoto(o: JSONObject) = PhotoRef(
        id = o.getString("id"), file = o.getString("file"), width = o.getInt("w"), height = o.getInt("h"),
        exif = o.optInt("exif", 1),
        faces = o.optJSONArray("faces")?.let { a -> List(a.length()) { a.getJSONArray(it).toRect() } },
    )

    private fun readAdjust(o: JSONObject?) = if (o == null) Adjustments() else Adjustments(
        o.f("brightness", 0f), o.f("contrast", 0f), o.f("saturation", 0f), o.f("warmth", 0f), o.f("sharpness", 0f),
    )

    private fun readCell(o: JSONObject): CellEdit {
        val cap = o.optJSONObject("caption")
        return CellEdit(
            photo = o.optJSONObject("photo")?.let(::readPhoto),
            zoom = o.f("zoom", 1f), cx = o.f("cx", 0.5f), cy = o.f("cy", 0.5f),
            rotation = o.optInt("rotation", 0), mirror = o.optBoolean("mirror", false),
            fit = o.optBoolean("fit", false), manual = o.optBoolean("manual", false),
            adjustments = readAdjust(o.optJSONObject("adjust")),
            filter = enumOf(o.optString("filter"), FilterType.NONE),
            caption = CellCaption(cap?.optString("name") ?: "", cap?.optString("relation") ?: "", cap?.optString("age") ?: ""),
        )
    }

    private fun readText(o: JSONObject) = TextOverlay(
        id = o.getString("id"), text = o.optString("text"), x = o.f("x", 0.5f), y = o.f("y", 0.9f),
        size = o.f("size", 0.06f), color = o.optInt("color", -1), font = enumOf(o.optString("font"), FontChoice.SANS),
        bold = o.optBoolean("bold"), italic = o.optBoolean("italic"), align = enumOf(o.optString("align"), TextAlign.CENTER),
        shadow = o.optBoolean("shadow", true), backgroundColor = o.optInt("bg", 0), rotation = o.f("rot", 0f),
    )

    private fun readBackground(o: JSONObject?) = if (o == null) Background() else Background(
        type = enumOf(o.optString("type"), BackgroundType.SOLID), color1 = o.optInt("c1", -1),
        color2 = o.optInt("c2", 0xFFE9E4DC.toInt()), texture = enumOf(o.optString("texture"), TextureKind.PAPER),
        angle = o.f("angle", 90f),
    )

    private fun readStyle(o: JSONObject?) = if (o == null) CollageStyle() else CollageStyle(
        spacing = o.f("spacing", 0.012f), margin = o.f("margin", 0.012f), cornerRadius = o.f("radius", 0.03f),
        borderWidth = o.f("border", 0f), borderColor = o.optInt("borderColor", -1),
    )

    private fun readCanvas(o: JSONObject?) = if (o == null) CanvasSpec.SQUARE
    else CanvasSpec(o.optInt("w", 1).coerceIn(1, 99), o.optInt("h", 1).coerceIn(1, 99), o.optString("label", "1:1"))

    private fun readLayout(o: JSONObject): LayoutTemplate {
        val a = o.getJSONArray("cells")
        return LayoutTemplate(o.getString("id"), o.optString("name"), List(a.length()) { a.getJSONArray(it).toRect() })
    }

    fun parseProject(json: String): CollageProject = parseProject(JSONObject(json))

    fun parseProject(o: JSONObject): CollageProject {
        val layout = readLayout(o.getJSONObject("layout"))
        val cellsArr = o.optJSONArray("cells") ?: JSONArray()
        val cells = List(cellsArr.length()) { readCell(cellsArr.getJSONObject(it)) }
        val textsArr = o.optJSONArray("texts") ?: JSONArray()
        return CollageProject(
            version = CollageProject.CURRENT_VERSION,
            id = o.getString("id"), name = o.optString("name", "Untitled collage"),
            createdAt = o.optLong("createdAt"), updatedAt = o.optLong("updatedAt"),
            mode = enumOf(o.optString("mode"), ProjectMode.COLLAGE),
            canvas = readCanvas(o.optJSONObject("canvas")), layout = layout,
            style = readStyle(o.optJSONObject("style")), background = readBackground(o.optJSONObject("background")),
            // pad/trim so cells always match the layout
            cells = List(layout.count) { cells.getOrNull(it) ?: CellEdit() },
            texts = List(textsArr.length()) { readText(textsArr.getJSONObject(it)) },
            faceMode = enumOf(o.optString("faceMode"), FaceMode.SMART),
        )
    }

    fun parseTemplate(o: JSONObject) = SavedTemplate(
        id = o.getString("id"), name = o.optString("name", "Template"), mode = enumOf(o.optString("mode"), ProjectMode.COLLAGE),
        canvas = readCanvas(o.optJSONObject("canvas")), layout = readLayout(o.getJSONObject("layout")),
        style = readStyle(o.optJSONObject("style")), background = readBackground(o.optJSONObject("background")),
    )
}
