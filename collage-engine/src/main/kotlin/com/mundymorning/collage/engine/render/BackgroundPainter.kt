package com.mundymorning.collage.engine.render

import android.graphics.Bitmap
import android.graphics.BitmapShader
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.LinearGradient
import android.graphics.Paint
import android.graphics.Shader
import com.mundymorning.collage.engine.project.Background
import com.mundymorning.collage.engine.project.BackgroundType
import com.mundymorning.collage.engine.project.TextureKind
import kotlin.math.cos
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin

/** Draws canvas backgrounds. Textures are generated procedurally (no asset files) and scale with the canvas. */
object BackgroundPainter {

    fun draw(canvas: Canvas, w: Int, h: Int, bg: Background, keepTransparent: Boolean) {
        val p = Paint(Paint.ANTI_ALIAS_FLAG)
        when (bg.type) {
            BackgroundType.TRANSPARENT -> if (!keepTransparent) canvas.drawColor(Color.WHITE)
            BackgroundType.SOLID -> canvas.drawColor(bg.color1)
            BackgroundType.GRADIENT -> {
                val a = Math.toRadians(bg.angle.toDouble())
                val cx = w / 2f; val cy = h / 2f
                val len = (w + h) / 2f
                p.shader = LinearGradient(
                    cx - cos(a).toFloat() * len / 2, cy - sin(a).toFloat() * len / 2,
                    cx + cos(a).toFloat() * len / 2, cy + sin(a).toFloat() * len / 2,
                    bg.color1, bg.color2, Shader.TileMode.CLAMP,
                )
                canvas.drawRect(0f, 0f, w.toFloat(), h.toFloat(), p)
            }
            BackgroundType.TEXTURE -> {
                canvas.drawColor(bg.color1)
                texture(canvas, w, h, bg)
            }
        }
    }

    private fun texture(canvas: Canvas, w: Int, h: Int, bg: Background) {
        val side = min(w, h).toFloat()
        val ink = bg.color2
        when (bg.texture) {
            TextureKind.PAPER, TextureKind.GRAIN -> {
                val tile = noiseTile(ink, if (bg.texture == TextureKind.PAPER) 38 else 70)
                val p = Paint().apply { shader = BitmapShader(tile, Shader.TileMode.REPEAT, Shader.TileMode.REPEAT); isFilterBitmap = true }
                val scale = if (bg.texture == TextureKind.PAPER) side / 300f else side / 600f
                canvas.save(); canvas.scale(max(scale, 0.5f), max(scale, 0.5f))
                canvas.drawRect(0f, 0f, w / max(scale, 0.5f), h / max(scale, 0.5f), p)
                canvas.restore()
            }
            TextureKind.LINEN -> {
                val step = max(2f, side / 120f)
                val p = Paint().apply { color = withAlpha(ink, 38); strokeWidth = max(1f, step / 3f) }
                var x = 0f
                while (x < w) { canvas.drawLine(x, 0f, x, h.toFloat(), p); x += step }
                var y = step / 2f
                p.color = withAlpha(ink, 26)
                while (y < h) { canvas.drawLine(0f, y, w.toFloat(), y, p); y += step }
            }
            TextureKind.DOTS -> {
                val step = side / 14f
                val p = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = withAlpha(ink, 90) }
                var row = 0
                var y = step / 2
                while (y < h + step) {
                    var x = if (row % 2 == 0) step / 2 else step
                    while (x < w + step) { canvas.drawCircle(x, y, step * 0.11f, p); x += step }
                    y += step / 1.6f; row++
                }
            }
            TextureKind.STRIPES -> {
                val step = side / 16f
                val p = Paint().apply { color = withAlpha(ink, 60) }
                var x = -h.toFloat()
                canvas.save(); canvas.rotate(-45f, w / 2f, h / 2f)
                val big = max(w, h) * 1.6f
                x = -big
                while (x < big) { canvas.drawRect(x, -big, x + step / 2, big, p); x += step }
                canvas.restore()
            }
            TextureKind.CHECKER -> {
                val step = side / 12f
                val p = Paint().apply { color = withAlpha(ink, 55) }
                var iy = 0; var y = 0f
                while (y < h) {
                    var ix = 0; var x = 0f
                    while (x < w) { if ((ix + iy) % 2 == 0) canvas.drawRect(x, y, x + step, y + step, p); x += step; ix++ }
                    y += step; iy++
                }
            }
        }
    }

    private fun withAlpha(c: Int, a: Int) = (c and 0x00FFFFFF) or (a shl 24)

    /** Deterministic 128px noise tile so exports look identical every time. */
    private fun noiseTile(ink: Int, maxAlpha: Int): Bitmap {
        val n = 128
        val rnd = java.util.Random(42)
        val px = IntArray(n * n) { withAlpha(ink, rnd.nextInt(maxAlpha)) }
        return Bitmap.createBitmap(px, n, n, Bitmap.Config.ARGB_8888)
    }
}
