package com.mundymorning.collage.engine.render

import android.graphics.Bitmap
import android.graphics.BitmapShader
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.ColorMatrix
import android.graphics.ColorMatrixColorFilter
import android.graphics.LinearGradient
import android.graphics.Matrix
import android.graphics.Paint
import android.graphics.Path
import android.graphics.RectF
import android.graphics.Shader
import android.graphics.Typeface
import android.text.Layout
import android.text.StaticLayout
import android.text.TextPaint
import com.mundymorning.collage.engine.color.ColorMath
import com.mundymorning.collage.engine.color.Sharpen
import com.mundymorning.collage.engine.io.BitmapProvider
import com.mundymorning.collage.engine.layout.LayoutEngine
import com.mundymorning.collage.engine.model.FRect
import com.mundymorning.collage.engine.project.CellEdit
import com.mundymorning.collage.engine.project.CollageProject
import com.mundymorning.collage.engine.project.TextAlign
import com.mundymorning.collage.engine.project.TextOverlay
import com.mundymorning.collage.engine.transform.CropMath
import com.mundymorning.collage.engine.transform.Orientation
import kotlin.math.max
import kotlin.math.min

/**
 * Renders a project to a bitmap at any resolution. The same code path serves the live preview and the final
 * export, so what you see is what you save. Originals are only ever read.
 */
class CollageRenderer(private val provider: BitmapProvider) {

    data class Options(
        /** Keep alpha for a transparent background (PNG). When false, transparent backgrounds render white. */
        val keepTransparent: Boolean = false,
        /** Draw placeholders for empty cells (editor only). */
        val showPlaceholders: Boolean = false,
    )

    fun render(project: CollageProject, width: Int, height: Int, options: Options = Options()): Bitmap {
        val bmp = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bmp)
        BackgroundPainter.draw(canvas, width, height, project.background, options.keepTransparent)
        val unit = LayoutEngine.unit(width.toFloat(), height.toFloat())
        val rects = cellRects(project, width, height)
        project.cells.forEachIndexed { i, cell ->
            val r = rects.getOrNull(i) ?: return@forEachIndexed
            drawCell(canvas, cell, r, project, unit, options)
        }
        project.texts.forEach { drawText(canvas, it, width, height) }
        return bmp
    }

    // ---------------------------------------------------------------- cells

    private fun drawCell(canvas: Canvas, cell: CellEdit, rect: FRect, project: CollageProject, unit: Float, options: Options) {
        val ref = cell.photo
        if (ref == null) {
            if (options.showPlaceholders) drawPlaceholder(canvas, rect, project, unit)
            return
        }
        val disp = Orientation.displaySize(ref.width, ref.height, ref.exif, cell.rotation)
        val region = CropMath.region(disp.aspect, rect.w / rect.h, cell.zoom, cell.cx, cell.cy, cell.fit)
        val part = CropMath.photoPart(region)
        val dest = CropMath.destRect(region, rect)
        val radius = min(project.style.cornerRadius * unit, min(dest.w, dest.h) / 2f)

        val pxPerSrc = dest.w / (part.w * disp.w)
        val bmp = provider.get(ref, CropMath.sampleFor(pxPerSrc))
        if (bmp == null) { drawBroken(canvas, dest, radius); return }
        try {
            paintCell(canvas, bmp, cell, rect, project, unit, allowSharpen = true)
        } finally {
            provider.release(bmp)
        }
    }

    /**
     * Paints one photo cell from an already decoded bitmap (any sample size). Used by [drawCell] and by live
     * gesture drawing, so what you see while dragging is exactly what is rendered afterwards.
     */
    private fun paintCell(canvas: Canvas, bmp: Bitmap, cell: CellEdit, rect: FRect, project: CollageProject, unit: Float, allowSharpen: Boolean) {
        val ref = cell.photo ?: return
        val disp = Orientation.displaySize(ref.width, ref.height, ref.exif, cell.rotation)
        val region = CropMath.region(disp.aspect, rect.w / rect.h, cell.zoom, cell.cx, cell.cy, cell.fit)
        val part = CropMath.photoPart(region)
        val dest = CropMath.destRect(region, rect)
        val radius = min(project.style.cornerRadius * unit, min(dest.w, dest.h) / 2f)
        run {
            val aff = Orientation.totalAffine(bmp.width, bmp.height, ref.exif, cell.rotation, cell.mirror)
            val dw = Orientation.displaySize(bmp.width, bmp.height, ref.exif, cell.rotation)
            val sx = dest.w / (part.w * dw.w)
            val sy = dest.h / (part.h * dw.h)
            val tx = dest.l - part.l * dest.w / part.w
            val ty = dest.t - part.t * dest.h / part.h
            val full = aff.then(com.mundymorning.collage.engine.transform.Affine(a = sx, d = sy, tx = tx, ty = ty))
            val matrix = Matrix().apply { setValues(full.toMatrixValues()) }

            val cm = ColorMath.forCell(cell.adjustments, cell.filter)
            val paint = Paint(Paint.ANTI_ALIAS_FLAG or Paint.FILTER_BITMAP_FLAG).apply {
                isFilterBitmap = true
                if (!ColorMath.isIdentity(cm)) colorFilter = ColorMatrixColorFilter(ColorMatrix(cm))
            }
            val rf = RectF(dest.l, dest.t, dest.r, dest.b)

            if (allowSharpen && cell.adjustments.sharpness > 0.001f && drawSharpened(canvas, bmp, matrix, paint, rf, radius, cell.adjustments.sharpness)) {
                // done
            } else {
                paint.shader = BitmapShader(bmp, Shader.TileMode.CLAMP, Shader.TileMode.CLAMP).also { it.setLocalMatrix(matrix) }
                canvas.drawRoundRect(rf, radius, radius, paint)
            }
            if (project.style.borderWidth > 0f) {
                val bw = project.style.borderWidth * unit
                val bp = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                    style = Paint.Style.STROKE; strokeWidth = bw; color = project.style.borderColor
                }
                val inset = bw / 2f
                canvas.drawRoundRect(
                    RectF(rf.left + inset, rf.top + inset, rf.right - inset, rf.bottom - inset),
                    max(0f, radius - inset), max(0f, radius - inset), bp,
                )
            }
            if (!cell.caption.isBlank) drawCaption(canvas, cell.caption.display(), rf, radius)
        }
    }

    /**
     * Repaints a single cell (background, photo, border, caption and text overlays) onto [canvas], typically a
     * hardware canvas, using the live crop in [cell]. Nothing is decoded, no bitmap is allocated and the project is
     * not touched, which makes it cheap enough to run every display frame while a finger is dragging.
     * Sharpening is skipped while live (it is applied by the final render).
     */
    fun drawCellLive(canvas: Canvas, project: CollageProject, index: Int, cell: CellEdit, bmp: Bitmap, width: Int, height: Int) {
        val rect = cellRects(project, width, height).getOrNull(index) ?: return
        val unit = LayoutEngine.unit(width.toFloat(), height.toFloat())
        canvas.save()
        canvas.clipRect(rect.l, rect.t, rect.r, rect.b)
        if (project.background.type == com.mundymorning.collage.engine.project.BackgroundType.TRANSPARENT) {
            canvas.drawColor(0, android.graphics.PorterDuff.Mode.CLEAR)
        } else {
            BackgroundPainter.draw(canvas, width, height, project.background, keepTransparent = true)
        }
        paintCell(canvas, bmp, cell, rect, project, unit, allowSharpen = false)
        project.texts.forEach { drawText(canvas, it, width, height) }
        canvas.restore()
    }

    /** Colour-correct into a cell-sized temp bitmap, sharpen, then draw with the rounded mask. */
    private fun drawSharpened(canvas: Canvas, src: Bitmap, matrix: Matrix, paint: Paint, rf: RectF, radius: Float, amount: Float): Boolean {
        val w = rf.width().toInt().coerceAtLeast(1)
        val h = rf.height().toInt().coerceAtLeast(1)
        if (w.toLong() * h > 40_000_000L) return false
        return try {
            val tmp = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
            val tc = Canvas(tmp)
            val m = Matrix(matrix).apply { postTranslate(-rf.left, -rf.top) }
            val p = Paint(paint).apply {
                shader = BitmapShader(src, Shader.TileMode.CLAMP, Shader.TileMode.CLAMP).also { it.setLocalMatrix(m) }
            }
            tc.drawRect(0f, 0f, w.toFloat(), h.toFloat(), p)
            val px = IntArray(w * h)
            tmp.getPixels(px, 0, w, 0, 0, w, h)
            val sharp = Sharpen.apply(px, w, h, amount)
            tmp.setPixels(sharp, 0, w, 0, 0, w, h)
            val dp = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                shader = BitmapShader(tmp, Shader.TileMode.CLAMP, Shader.TileMode.CLAMP)
                    .also { it.setLocalMatrix(Matrix().apply { setTranslate(rf.left, rf.top) }) }
            }
            canvas.drawRoundRect(rf, radius, radius, dp)
            tmp.recycle()
            true
        } catch (e: OutOfMemoryError) {
            false // skip sharpening rather than fail the whole render
        }
    }

    private fun drawCaption(canvas: Canvas, text: String, rf: RectF, radius: Float) {
        val base = min(rf.width(), rf.height())
        val size = max(base * 0.062f, 10f)
        val tp = TextPaint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.WHITE; textSize = size; typeface = Typeface.create("sans-serif-medium", Typeface.NORMAL)
            setShadowLayer(size * 0.15f, 0f, size * 0.05f, 0x99000000.toInt())
        }
        val pad = size * 0.8f
        val avail = (rf.width() - 2 * pad).toInt().coerceAtLeast(10)
        val layout = StaticLayout.Builder.obtain(text, 0, text.length, tp, avail)
            .setAlignment(Layout.Alignment.ALIGN_CENTER).setMaxLines(2).setEllipsize(android.text.TextUtils.TruncateAt.END).build()
        val scrimH = layout.height + pad * 2f
        canvas.save()
        val clip = Path().apply { addRoundRect(rf, radius, radius, Path.Direction.CW) }
        canvas.clipPath(clip)
        val sp = Paint().apply {
            shader = LinearGradient(0f, rf.bottom - scrimH, 0f, rf.bottom, 0x00000000, 0xB0000000.toInt(), Shader.TileMode.CLAMP)
        }
        canvas.drawRect(rf.left, rf.bottom - scrimH, rf.right, rf.bottom, sp)
        canvas.translate(rf.left + pad, rf.bottom - pad - layout.height)
        layout.draw(canvas)
        canvas.restore()
    }

    private fun drawPlaceholder(canvas: Canvas, rect: FRect, project: CollageProject, unit: Float) {
        val rf = RectF(rect.l, rect.t, rect.r, rect.b)
        val r = min(project.style.cornerRadius * unit, min(rect.w, rect.h) / 2f)
        val p = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = 0x33808080 }
        canvas.drawRoundRect(rf, r, r, p)
        p.color = 0x99808080.toInt(); p.strokeWidth = max(2f, min(rect.w, rect.h) * 0.02f); p.strokeCap = Paint.Cap.ROUND
        val s = min(rect.w, rect.h) * 0.12f
        canvas.drawLine(rect.cx - s, rect.cy, rect.cx + s, rect.cy, p)
        canvas.drawLine(rect.cx, rect.cy - s, rect.cx, rect.cy + s, p)
    }

    private fun drawBroken(canvas: Canvas, dest: FRect, radius: Float) {
        val p = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = 0xFF7A7A7A.toInt() }
        canvas.drawRoundRect(RectF(dest.l, dest.t, dest.r, dest.b), radius, radius, p)
    }

    // ---------------------------------------------------------------- text

    private fun textPaint(t: TextOverlay, canvasMin: Float): TextPaint = TextPaint(Paint.ANTI_ALIAS_FLAG).apply {
        textSize = max(4f, t.size * canvasMin)
        color = t.color
        val style = when {
            t.bold && t.italic -> Typeface.BOLD_ITALIC
            t.bold -> Typeface.BOLD
            t.italic -> Typeface.ITALIC
            else -> Typeface.NORMAL
        }
        typeface = Typeface.create(t.font.family, style)
        if (t.shadow) setShadowLayer(textSize * 0.12f, 0f, textSize * 0.04f, 0xAA000000.toInt())
    }

    private fun layoutFor(t: TextOverlay, w: Int, h: Int): StaticLayout {
        val tp = textPaint(t, min(w, h).toFloat())
        val maxW = (w * 0.9f).toInt().coerceAtLeast(10)
        val text = t.text.ifEmpty { " " }
        val natural = StaticLayout.getDesiredWidth(text, tp).toInt()
        val lines = text.lines().maxOfOrNull { StaticLayout.getDesiredWidth(it.ifEmpty { " " }, tp) }?.toInt() ?: natural
        val width = min(maxW, max(lines, 1) + 2)
        val align = when (t.align) {
            TextAlign.LEFT -> Layout.Alignment.ALIGN_NORMAL
            TextAlign.CENTER -> Layout.Alignment.ALIGN_CENTER
            TextAlign.RIGHT -> Layout.Alignment.ALIGN_OPPOSITE
        }
        return StaticLayout.Builder.obtain(text, 0, text.length, tp, width).setAlignment(align).build()
    }

    private fun drawText(canvas: Canvas, t: TextOverlay, w: Int, h: Int) {
        if (t.text.isBlank()) return
        val layout = layoutFor(t, w, h)
        canvas.save()
        canvas.translate(t.x * w, t.y * h)
        canvas.rotate(t.rotation)
        if (t.backgroundColor != 0) {
            val pad = layout.paint.textSize * 0.4f
            val p = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = t.backgroundColor }
            canvas.drawRoundRect(
                RectF(-layout.width / 2f - pad, -layout.height / 2f - pad * 0.6f, layout.width / 2f + pad, layout.height / 2f + pad * 0.6f),
                pad, pad, p,
            )
        }
        canvas.translate(-layout.width / 2f, -layout.height / 2f)
        layout.draw(canvas)
        canvas.restore()
    }

    /** Axis-aligned hit boxes (canvas pixels) for text overlays; used by the editor to drag text. */
    fun textBounds(project: CollageProject, w: Int, h: Int): List<RectF> = project.texts.map { t ->
        if (t.text.isBlank()) RectF() else {
            val l = layoutFor(t, w, h)
            val pad = l.paint.textSize * 0.4f
            RectF(t.x * w - l.width / 2f - pad, t.y * h - l.height / 2f - pad, t.x * w + l.width / 2f + pad, t.y * h + l.height / 2f + pad)
        }
    }

    companion object {
        fun cellRects(project: CollageProject, width: Int, height: Int): List<FRect> {
            val unit = LayoutEngine.unit(width.toFloat(), height.toFloat())
            return LayoutEngine.cellRects(
                project.layout, width.toFloat(), height.toFloat(), project.style.margin * unit, project.style.spacing * unit,
            )
        }
    }
}
