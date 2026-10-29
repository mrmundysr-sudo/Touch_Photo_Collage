package com.mundymorning.touchphotocollage.ui

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.Image
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.gestures.drag
import androidx.compose.foundation.layout.Box
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.ui.graphics.CompositingStrategy
import androidx.compose.ui.graphics.drawscope.drawIntoCanvas
import androidx.compose.ui.graphics.nativeCanvas
import androidx.compose.ui.graphics.graphicsLayer
import android.graphics.Bitmap
import com.mundymorning.collage.engine.transform.Orientation
import com.mundymorning.touchgesture.GestureOutcome
import com.mundymorning.touchgesture.OneFingerMath
import com.mundymorning.touchgesture.touchGesture
import com.mundymorning.touchphotocollage.LiveGesture
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
import com.mundymorning.touchgesture.label
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
    live: LiveGesture,
    renderer: CollageRenderer,
    liveBitmap: (Int) -> Bitmap?,
    onCommit: (index: Int, zoom: Float, cx: Float, cy: Float) -> Unit,
    sensitivity: Float,
) {
    val density = LocalDensity.current
    val haptics = LocalHapticFeedback.current
    val rects = remember(project.layout, project.style, project.canvas, widthPx, heightPx) { CollageRenderer.cellRects(project, widthPx, heightPx) }
    val rectsState = rememberUpdatedState(rects)
    val frameState = rememberUpdatedState(frame)
    val projectState = rememberUpdatedState(project)
    val modeState = rememberUpdatedState(mode)
    val sensState = rememberUpdatedState(sensitivity)
    val liveBitmapState = rememberUpdatedState(liveBitmap)
    val onCommitState = rememberUpdatedState(onCommit)
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
                    val photo = cell?.photo ?: return@awaitEachGesture
                    val fit = cell.fit
                    val imgAspect = Orientation.displaySize(photo.width, photo.height, photo.exif, cell.rotation).aspect
                    var fallback = false

                    val outcome = touchGesture(
                        down, modeState.value, pinchState.value,
                        pxPerDoubling = OneFingerMath.pxPerDoubling(1.dp.toPx(), sensState.value),
                        deadzonePx = 4.dp.toPx(),
                        stillnessPx = 2.dp.toPx(),
                        onBegin = {
                            val bmp = liveBitmapState.value(idx)
                            val c = projectState.value.cells[idx]
                            if (bmp != null) live.begin(idx, c.zoom, c.cx, c.cy, bmp) else fallback = true
                        },
                        onPan = { d ->
                            val r = rectsState.value[idx]
                            if (fallback) onTransform(idx, d.x, d.y, 1f, 0.5f, 0.5f, r.w, r.h)
                            else live.pan(d.x, d.y, imgAspect, r.w, r.h, fit)
                        },
                        onZoom = { factor, centroid ->
                            val r = rectsState.value[idx]
                            val fx = centroid?.let { ((it.x - r.l) / r.w).coerceIn(0f, 1f) } ?: 0.5f
                            val fy = centroid?.let { ((it.y - r.t) / r.h).coerceIn(0f, 1f) } ?: 0.5f
                            if (fallback) onTransform(idx, 0f, 0f, factor, fx, fy, r.w, r.h)
                            else live.zoomBy(factor, fx, fy, imgAspect, r.w / r.h, fit)
                        },
                    )
                    when (outcome) {
                        GestureOutcome.MOVED -> {
                            if (fallback) onGestureEnd()
                            else if (live.active) {
                                onCommitState.value(idx, live.zoom, live.cx, live.cy)
                                live.markCommitted()
                            }
                        }
                        GestureOutcome.TAP -> { live.clear(); if (fallback) onGestureEnd() }
                        GestureOutcome.LONG_PRESS -> {
                            live.clear()
                            haptics.performHapticFeedback(HapticFeedbackType.LongPress)
                            dragFrom = idx; dragPos = start
                            drag(down.id) { ch -> ch.consume(); dragPos = ch.position }
                            val to = rectsState.value.indexOfFirst { it.contains(dragPos.x, dragPos.y) }
                            dragFrom = null
                            if (to >= 0 && to != idx) onSwap(idx, to)
                        }
                    }
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
        // The rendered frame and the live layer share one offscreen layer so a transparent background can be cleared.
        Box(Modifier.size(with(density) { widthPx.toDp() }, with(density) { heightPx.toDp() }).graphicsLayer { compositingStrategy = CompositingStrategy.Offscreen }) {
            frame?.let {
                Image(it.bitmap.asImageBitmap(), null, Modifier.size(with(density) { widthPx.toDp() }, with(density) { heightPx.toDp() }), contentScale = ContentScale.FillBounds)
            }
            Canvas(Modifier.size(with(density) { widthPx.toDp() }, with(density) { heightPx.toDp() })) {
                // Reads live.* here, in the draw phase only: a touch event invalidates just this draw.
                if (live.active) {
                    val bmp = live.bitmap
                    val p = projectState.value
                    val base = p.cells.getOrNull(live.index)
                    if (bmp != null && base != null) {
                        val cell = base.copy(zoom = live.zoom, cx = live.cx, cy = live.cy)
                        drawIntoCanvas { c -> renderer.drawCellLive(c.nativeCanvas, p, live.index, cell, bmp, widthPx, heightPx) }
                    }
                }
            }
        }
        // Remove the live layer once the committed project's frame is what is on screen.
        val pending = live.commitPending
        LaunchedEffect(frame, pending) {
            if (pending && frame != null) {
                val c = frame.forProject.cells.getOrNull(live.index)
                if (c != null && c.zoom == live.zoom && c.cx == live.cx && c.cy == live.cy) live.clear()
            }
        }
        LaunchedEffect(pending) { if (pending) { kotlinx.coroutines.delay(1500); live.clear() } }
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
