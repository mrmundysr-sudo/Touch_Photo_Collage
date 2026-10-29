package com.mundymorning.touchphotocollage.ui

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.Image
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.gestures.drag
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.size
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.input.pointer.positionChanged
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.semantics.CustomAccessibilityAction
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.customActions
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.unit.dp
import com.mundymorning.collage.engine.model.FRect
import com.mundymorning.collage.engine.project.BackgroundType
import com.mundymorning.collage.engine.project.CollageProject
import com.mundymorning.collage.engine.render.CollageRenderer
import com.mundymorning.touchgesture.TouchMode
import com.mundymorning.touchgesture.TouchStart
import com.mundymorning.touchgesture.classifyTouchStart
import com.mundymorning.touchgesture.label
import com.mundymorning.touchgesture.oneFingerOrPinchGesture
import com.mundymorning.touchphotocollage.PreviewFrame
import com.mundymorning.touchphotocollage.Selection

/**
 * The live canvas. One finger drags the photo inside its cell, two fingers pinch-zoom it, a long press picks
 * the cell up so it can be dropped on another one to swap, and dragging text moves it.
 */
@Composable
fun CollageCanvas(
    project: CollageProject,
    frame: PreviewFrame?,
    widthPx: Int,
    heightPx: Int,
    selection: Selection,
    onSelectCell: (Int?) -> Unit,
    onSelectText: (Int?) -> Unit,
    onTransform: (index: Int, panX: Float, panY: Float, zoom: Float, fx: Float, fy: Float, cw: Float, ch: Float) -> Unit,
    onMoveText: (index: Int, nx: Float, ny: Float) -> Unit,
    onSwap: (Int, Int) -> Unit,
    onGestureEnd: () -> Unit,
    mode: TouchMode,
    pinchEnabled: Boolean,
    onZoomStep: (Float) -> Unit,
    onPanStep: (Float, Float) -> Unit,
    onReset: () -> Unit,
) {
    val density = LocalDensity.current
    val haptics = LocalHapticFeedback.current
    val rects = remember(project.layout, project.style, project.canvas, widthPx, heightPx) { CollageRenderer.cellRects(project, widthPx, heightPx) }
    val rectsState = rememberUpdatedState(rects)
    val frameState = rememberUpdatedState(frame)
    val projectState = rememberUpdatedState(project)
    val modeState = rememberUpdatedState(mode)
    val pinchState = rememberUpdatedState(pinchEnabled)
    var dragFrom by remember { mutableStateOf<Int?>(null) }
    var dragPos by remember { mutableStateOf(Offset.Zero) }
    val primary = MaterialTheme.colorScheme.primary
    val checkA = Color(0xFFE6E6E6); val checkB = Color(0xFFFFFFFF)
    val transparent = project.background.type == BackgroundType.TRANSPARENT

    Box(
        Modifier.size(with(density) { widthPx.toDp() }, with(density) { heightPx.toDp() }).clipToBounds()
            .semantics {
                contentDescription = "Collage preview with ${project.photoCount} photos. Current touch mode: ${mode.label}. Long press a photo and drop it onto another to swap."
                customActions = listOf(
                    CustomAccessibilityAction("Zoom in on selected photo") { onZoomStep(1.25f); true },
                    CustomAccessibilityAction("Zoom out on selected photo") { onZoomStep(0.8f); true },
                    CustomAccessibilityAction("Move selected photo left") { onPanStep(-0.1f, 0f); true },
                    CustomAccessibilityAction("Move selected photo right") { onPanStep(0.1f, 0f); true },
                    CustomAccessibilityAction("Move selected photo up") { onPanStep(0f, -0.1f); true },
                    CustomAccessibilityAction("Move selected photo down") { onPanStep(0f, 0.1f); true },
                    CustomAccessibilityAction("Reset selected photo position") { onReset(); true },
                )
            }
            .pointerInput(widthPx, heightPx) {
                awaitEachGesture {
                    val down = awaitFirstDown(requireUnconsumed = false)
                    val start = down.position
                    val textIdx = frameState.value?.textBounds?.indexOfLast { it.contains(start.x, start.y) } ?: -1
                    if (textIdx >= 0) {
                        onSelectText(textIdx)
                        val t0 = projectState.value.texts[textIdx]
                        val ox = t0.x * widthPx - start.x
                        val oy = t0.y * heightPx - start.y
                        drag(down.id) { ch ->
                            ch.consume()
                            onMoveText(textIdx, (ch.position.x + ox) / widthPx, (ch.position.y + oy) / heightPx)
                        }
                        onGestureEnd()
                        return@awaitEachGesture
                    }
                    val idx = rectsState.value.indexOfFirst { it.contains(start.x, start.y) }
                    if (idx < 0) { onSelectCell(null); return@awaitEachGesture }
                    onSelectCell(idx)
                    val cell = projectState.value.cells.getOrNull(idx)
                    if (cell?.photo == null) return@awaitEachGesture

                    var startDelta = Offset.Zero
                    val kind = classifyTouchStart(down) { startDelta = it }
                    if (kind == TouchStart.TAP) return@awaitEachGesture
                    if (kind == TouchStart.LONG_PRESS) {
                        haptics.performHapticFeedback(HapticFeedbackType.LongPress)
                        dragFrom = idx; dragPos = start
                        drag(down.id) { ch -> ch.consume(); dragPos = ch.position }
                        val to = rectsState.value.indexOfFirst { it.contains(dragPos.x, dragPos.y) }
                        dragFrom = null
                        if (to >= 0 && to != idx) onSwap(idx, to)
                        return@awaitEachGesture
                    }
                    // one-finger PAN / ZOOM (Touch Gesture Standard) or optional pinch
                    val perDoubling = 160.dp.toPx()
                    val moved = oneFingerOrPinchGesture(
                        modeState.value, pinchState.value, perDoubling,
                        onPan = { d ->
                            val r = rectsState.value[idx]
                            onTransform(idx, d.x, d.y, 1f, 0.5f, 0.5f, r.w, r.h)
                        },
                        onZoom = { factor, centroid ->
                            val r = rectsState.value[idx]
                            val fx = centroid?.let { ((it.x - r.l) / r.w).coerceIn(0f, 1f) } ?: 0.5f
                            val fy = centroid?.let { ((it.y - r.t) / r.h).coerceIn(0f, 1f) } ?: 0.5f
                            onTransform(idx, 0f, 0f, factor, fx, fy, r.w, r.h)
                        },
                        initialDelta = startDelta,
                    )
                    if (moved) onGestureEnd()
                }
            },
    ) {
        if (transparent) Canvas(Modifier.size(with(density) { widthPx.toDp() }, with(density) { heightPx.toDp() })) {
            val s = 12.dp.toPx()
            var y = 0f; var r = 0
            while (y < size.height) {
                var x = 0f; var c = 0
                while (x < size.width) { drawRect(if ((r + c) % 2 == 0) checkA else checkB, Offset(x, y), Size(s, s)); x += s; c++ }
                y += s; r++
            }
        }
        frame?.let {
            Image(it.bitmap.asImageBitmap(), null, Modifier.size(with(density) { widthPx.toDp() }, with(density) { heightPx.toDp() }), contentScale = ContentScale.FillBounds)
        }
        // selection and drag overlays
        Canvas(Modifier.size(with(density) { widthPx.toDp() }, with(density) { heightPx.toDp() })) {
            selection.cell?.let { i ->
                rects.getOrNull(i)?.let { r ->
                    drawRoundRect(primary, Offset(r.l, r.t), Size(r.w, r.h), CornerRadius(6.dp.toPx()), style = Stroke(3.dp.toPx()))
                }
            }
            frame?.textBounds?.getOrNull(selection.text ?: -1)?.let { b ->
                drawRoundRect(primary, Offset(b.left, b.top), Size(b.width(), b.height()), CornerRadius(6.dp.toPx()), style = Stroke(2.dp.toPx(), pathEffect = androidx.compose.ui.graphics.PathEffect.dashPathEffect(floatArrayOf(14f, 10f))))
            }
            dragFrom?.let { from ->
                rects.getOrNull(from)?.let { r -> drawRoundRect(Color.Black.copy(alpha = 0.35f), Offset(r.l, r.t), Size(r.w, r.h), CornerRadius(6.dp.toPx())) }
                val target = rects.indexOfFirst { it.contains(dragPos.x, dragPos.y) }
                if (target >= 0 && target != from) rects[target].let { r ->
                    drawRoundRect(primary.copy(alpha = 0.35f), Offset(r.l, r.t), Size(r.w, r.h), CornerRadius(6.dp.toPx()))
                    drawRoundRect(primary, Offset(r.l, r.t), Size(r.w, r.h), CornerRadius(6.dp.toPx()), style = Stroke(4.dp.toPx()))
                }
                val w = 84.dp.toPx(); val h = w * 0.75f
                drawRoundRect(primary.copy(alpha = 0.85f), Offset(dragPos.x - w / 2, dragPos.y - h / 2), Size(w, h), CornerRadius(10.dp.toPx()))
            }
        }
    }
}

private fun FRect.contains(x: Float, y: Float) = x >= l && x <= r && y >= t && y <= b
private fun android.graphics.RectF.contains(x: Float, y: Float) = x >= left && x <= right && y >= top && y <= bottom
private val Offset.isSpecified: Boolean get() = this != Offset.Unspecified && !x.isNaN()
