package com.mundymorning.touchphotocollage.ui

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.FilterChip
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Slider
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.mundymorning.collage.engine.layout.LayoutTemplate

@Composable
fun SectionLabel(text: String, modifier: Modifier = Modifier) {
    Text(text, style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = modifier.padding(bottom = 4.dp))
}

/** Slider with a label and value, at least 48dp tall. */
@Composable
fun LabeledSlider(
    label: String, value: Float, range: ClosedFloatingPointRange<Float>, onChange: (Float) -> Unit, onDone: () -> Unit,
    valueText: (Float) -> String = { "${Math.round(it * 100)}" },
) {
    Column(Modifier.fillMaxWidth()) {
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
            Text(label, style = MaterialTheme.typography.labelLarge)
            Text(valueText(value), style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        Slider(
            value = value.coerceIn(range.start, range.endInclusive), onValueChange = onChange, onValueChangeFinished = onDone, valueRange = range,
            modifier = Modifier.height(32.dp).semantics { contentDescription = "$label ${valueText(value)}" },
        )
    }
}

@Composable
fun ChipRow(modifier: Modifier = Modifier, content: @Composable () -> Unit) {
    Row(modifier.horizontalScrollRow(), horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) { content() }
}

@Composable
private fun Modifier.horizontalScrollRow(): Modifier = this.horizontalScroll(rememberScrollState())

@Composable
fun SelectChip(label: String, selected: Boolean, onClick: () -> Unit) {
    FilterChip(selected = selected, onClick = onClick, label = { Text(label, maxLines = 1, overflow = TextOverflow.Ellipsis) })
}

val SwatchColors = listOf(
    0xFFFFFFFF, 0xFFF5EFE6, 0xFFE9DCC9, 0xFF1C1B1F, 0xFF424242, 0xFFE8613C, 0xFFFFC857, 0xFF3FA796, 0xFF4A90D9,
    0xFF7B6CF0, 0xFFE46A9B, 0xFF9BCB6B, 0xFFB5651D, 0xFFCFD8DC,
).map { it.toInt() }

@Composable
fun ColorSwatches(selected: Int?, onPick: (Int) -> Unit, modifier: Modifier = Modifier, colors: List<Int> = SwatchColors) {
    var custom by remember { mutableStateOf(false) }
    ChipRow(modifier) {
        colors.forEach { c ->
            val sel = selected == c
            Box(
                Modifier.size(36.dp).clip(CircleShape).background(Color(c))
                    .border(if (sel) BorderStroke(3.dp, MaterialTheme.colorScheme.primary) else BorderStroke(1.dp, MaterialTheme.colorScheme.outlineVariant), CircleShape)
                    .clickable { onPick(c) }
                    .semantics { role = Role.Button; contentDescription = "Colour ${String.format("#%06X", c and 0xFFFFFF)}" },
            )
        }
        Box(
            Modifier.size(36.dp).clip(CircleShape).border(1.dp, MaterialTheme.colorScheme.outline, CircleShape).clickable { custom = true }
                .semantics { contentDescription = "Custom colour" },
            contentAlignment = Alignment.Center,
        ) { Text("+", style = MaterialTheme.typography.titleMedium) }
    }
    if (custom) CustomColorDialog(selected ?: 0xFFFFFFFF.toInt(), { custom = false }) { onPick(it); custom = false }
}

@Composable
fun CustomColorDialog(initial: Int, onDismiss: () -> Unit, onPick: (Int) -> Unit) {
    val hsv = remember {
        val a = FloatArray(3); android.graphics.Color.colorToHSV(initial, a); a
    }
    var h by remember { mutableFloatStateOf(hsv[0]) }
    var s by remember { mutableFloatStateOf(hsv[1]) }
    var v by remember { mutableFloatStateOf(hsv[2]) }
    val color = android.graphics.Color.HSVToColor(floatArrayOf(h, s, v))
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("Custom colour") },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Box(Modifier.fillMaxWidth().height(48.dp).clip(RoundedCornerShape(12.dp)).background(Color(color)).border(1.dp, MaterialTheme.colorScheme.outlineVariant, RoundedCornerShape(12.dp)))
                LabeledSlider("Hue", h, 0f..360f, { h = it }, {}, { "${it.toInt()}°" })
                LabeledSlider("Richness", s, 0f..1f, { s = it }, {})
                LabeledSlider("Brightness", v, 0f..1f, { v = it }, {})
            }
        },
        confirmButton = { TextButton({ onPick(color) }) { Text("Use colour") } },
        dismissButton = { TextButton(onDismiss) { Text("Cancel") } },
    )
}

/** Mini diagram of a layout. */
@Composable
fun LayoutThumb(layout: LayoutTemplate, aspect: Float, selected: Boolean, onClick: () -> Unit, label: String = layout.name) {
    val primary = MaterialTheme.colorScheme.primary
    val cell = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.55f)
    Column(
        Modifier.width(72.dp).clip(RoundedCornerShape(12.dp)).clickable(onClick = onClick).padding(4.dp)
            .semantics { role = Role.Button; contentDescription = "Layout $label" },
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Box(
            Modifier.size(56.dp).border(if (selected) BorderStroke(2.dp, primary) else BorderStroke(1.dp, MaterialTheme.colorScheme.outlineVariant), RoundedCornerShape(8.dp)),
            contentAlignment = Alignment.Center,
        ) {
            Canvas(Modifier.size(44.dp)) {
                val a = aspect.coerceIn(0.4f, 2.5f)
                val w = if (a >= 1f) size.width else size.height * a
                val h = if (a >= 1f) size.width / a else size.height
                val ox = (size.width - w) / 2f; val oy = (size.height - h) / 2f
                val gap = 1.6.dp.toPx()
                layout.cells.forEach { c ->
                    drawRoundRect(
                        color = if (selected) primary else cell,
                        topLeft = Offset(ox + c.l * w + gap, oy + c.t * h + gap),
                        size = Size(((c.r - c.l) * w - 2 * gap).coerceAtLeast(1f), ((c.b - c.t) * h - 2 * gap).coerceAtLeast(1f)),
                        cornerRadius = CornerRadius(2.dp.toPx()),
                    )
                }
            }
        }
        Text(label, style = MaterialTheme.typography.labelSmall, maxLines = 1, overflow = TextOverflow.Ellipsis, color = if (selected) primary else MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

@Composable
fun TinyLabel(text: String) = Text(text, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)

fun Color.argb(): Int = this.toArgb()
