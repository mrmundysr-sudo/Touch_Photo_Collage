package com.mundymorning.touchgesture

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.runtime.withFrameNanos

/** Rolling frame statistics over a time window. Pure, unit-tested. */
class FrameStats(private val windowNanos: Long = 1_000_000_000L, private val jankNanos: Long = 20_000_000L) {
    private val times = ArrayDeque<Long>()
    private val durations = ArrayDeque<Long>()
    private var last = 0L

    /** Record a frame presented at [nowNanos]. */
    fun record(nowNanos: Long) {
        if (last != 0L) { times.addLast(nowNanos); durations.addLast(nowNanos - last) }
        last = nowNanos
        while (times.isNotEmpty() && nowNanos - times.first() > windowNanos) { times.removeFirst(); durations.removeFirst() }
    }

    val frames: Int get() = durations.size
    val avgMs: Float get() = if (durations.isEmpty()) 0f else durations.sum() / durations.size / 1e6f
    val worstMs: Float get() = (durations.maxOrNull() ?: 0L) / 1e6f
    val jankyFrames: Int get() = durations.count { it > jankNanos }
    val fps: Float get() = if (durations.isEmpty()) 0f else 1e9f / (durations.sum().toFloat() / durations.size)

    fun summary(): String = if (frames == 0) "frames: …" else "%.0f fps · avg %.1f ms · worst %.0f ms · janky %d".format(fps, avgMs, worstMs, jankyFrames)

    fun reset() { times.clear(); durations.clear(); last = 0L }
}

/**
 * Small overlay showing display-synchronised frame timing, to measure real-device smoothness. Only call it when the
 * user enabled it: the loop requests a frame every vsync while shown.
 */
@Composable
fun FrameTimingOverlay(modifier: Modifier = Modifier) {
    val stats = remember { FrameStats() }
    var text by remember { mutableStateOf("frames: …") }
    LocalContext.current
    LaunchedEffect(Unit) {
        var shown = 0L
        while (true) {
            withFrameNanos { now ->
                stats.record(now)
                if (now - shown > 400_000_000L) { shown = now; text = stats.summary() }
            }
        }
    }
    Text(
        text, color = Color.White, fontSize = 11.sp,
        modifier = modifier.clip(RoundedCornerShape(8.dp)).background(Color.Black.copy(alpha = 0.7f)).padding(horizontal = 8.dp, vertical = 4.dp),
    )
}
