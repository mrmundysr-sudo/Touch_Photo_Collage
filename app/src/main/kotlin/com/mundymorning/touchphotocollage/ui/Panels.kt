package com.mundymorning.touchphotocollage.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.FilterChip
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.ui.unit.dp
import com.mundymorning.collage.engine.layout.CanvasSpec
import com.mundymorning.collage.engine.layout.LayoutGenerator
import com.mundymorning.collage.engine.project.*
import com.mundymorning.touchphotocollage.CollageViewModel
import java.text.DateFormat
import java.util.Date

@Composable
fun LayoutPanel(vm: CollageViewModel, p: CollageProject) {
    val n = p.layout.count
    val candidates = remember(n) { LayoutGenerator.candidates(n) }
    var customCanvas by remember { mutableStateOf(false) }
    var saveTemplate by remember { mutableStateOf(false) }
    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
        SectionLabel("Arrangement")
        LazyRow(horizontalArrangement = Arrangement.spacedBy(4.dp)) {
            item {
                LayoutThumbAction("Auto", "✨") { vm.autoLayout() }
            }
            items(candidates, key = { it.id }) { l ->
                LayoutThumb(l, p.canvas.aspect, selected = l.id == p.layout.id, onClick = { vm.setLayout(l) })
            }
            if (p.layout.id.startsWith("mosaic") && p.layout.id !in candidates.map { it.id }) item {
                LayoutThumb(p.layout, p.canvas.aspect, true, {}, "Artistic")
            }
        }
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            if (n >= 2) OutlinedButton({ vm.shuffleArtistic() }) { Text("🎲 Shuffle artistic") }
            OutlinedButton({ saveTemplate = true }) { Text("Save as template") }
        }
        SectionLabel("Canvas shape")
        ChipRow {
            CanvasSpec.PRESETS.forEach { c ->
                val label = when (c) {
                    CanvasSpec.SQUARE -> "Square 1:1"; CanvasSpec.PORTRAIT_4_5 -> "Portrait 4:5"; CanvasSpec.PORTRAIT_3_4 -> "Portrait 3:4"
                    CanvasSpec.PORTRAIT_2_3 -> "Tall 2:3"; CanvasSpec.STORY_9_16 -> "Story 9:16"; CanvasSpec.LANDSCAPE_4_3 -> "Wide 4:3"
                    CanvasSpec.LANDSCAPE_3_2 -> "Wide 3:2"; CanvasSpec.WIDE_16_9 -> "Cinema 16:9"; else -> c.label
                }
                SelectChip(label, p.canvas.ratioW == c.ratioW && p.canvas.ratioH == c.ratioH) { vm.setCanvas(c) }
            }
            SelectChip(if (CanvasSpec.PRESETS.none { it.ratioW == p.canvas.ratioW && it.ratioH == p.canvas.ratioH }) "Custom ${p.canvas.label}" else "Custom…",
                CanvasSpec.PRESETS.none { it.ratioW == p.canvas.ratioW && it.ratioH == p.canvas.ratioH }) { customCanvas = true }
        }
    }
    if (customCanvas) {
        var w by remember { mutableStateOf(p.canvas.ratioW.toString()) }
        var h by remember { mutableStateOf(p.canvas.ratioH.toString()) }
        AlertDialog(
            onDismissRequest = { customCanvas = false },
            title = { Text("Custom canvas ratio") },
            text = {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    OutlinedTextField(w, { w = it.filter(Char::isDigit).take(2) }, label = { Text("Width") }, singleLine = true,
                        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number), modifier = Modifier.weight(1f))
                    Text(":")
                    OutlinedTextField(h, { h = it.filter(Char::isDigit).take(2) }, label = { Text("Height") }, singleLine = true,
                        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number), modifier = Modifier.weight(1f))
                }
            },
            confirmButton = {
                TextButton({
                    val a = w.toIntOrNull() ?: 0; val b = h.toIntOrNull() ?: 0
                    if (a > 0 && b > 0) vm.setCanvas(CanvasSpec.custom(a, b))
                    customCanvas = false
                }) { Text("Apply") }
            },
            dismissButton = { TextButton({ customCanvas = false }) { Text("Cancel") } },
        )
    }
    if (saveTemplate) {
        var name by remember { mutableStateOf("") }
        AlertDialog(
            onDismissRequest = { saveTemplate = false },
            title = { Text("Save as template") },
            text = {
                Column {
                    Text("Keeps the arrangement, canvas shape, spacing and background (not the photos).", style = MaterialTheme.typography.bodyMedium)
                    OutlinedTextField(name, { name = it.take(30) }, label = { Text("Template name") }, singleLine = true, modifier = Modifier.padding(top = 8.dp))
                }
            },
            confirmButton = { TextButton({ vm.saveTemplate(name); saveTemplate = false }) { Text("Save") } },
            dismissButton = { TextButton({ saveTemplate = false }) { Text("Cancel") } },
        )
    }
}

@Composable
private fun LayoutThumbAction(label: String, glyph: String, onClick: () -> Unit) {
    Column(
        Modifier.width(72.dp).padding(4.dp).let { it }.then(Modifier),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        OutlinedButton(onClick, Modifier.width(56.dp).height(56.dp), contentPadding = androidx.compose.foundation.layout.PaddingValues(0.dp)) { Text(glyph) }
        Text(label, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

@Composable
fun StylePanel(vm: CollageViewModel, p: CollageProject) {
    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        LabeledSlider("Spacing", p.style.spacing, 0f..0.08f, { v -> vm.setStyle { it.copy(spacing = v) } }, vm::endLive) { "${Math.round(it * 1000) / 10f}%" }
        LabeledSlider("Margin", p.style.margin, 0f..0.1f, { v -> vm.setStyle { it.copy(margin = v) } }, vm::endLive) { "${Math.round(it * 1000) / 10f}%" }
        LabeledSlider("Rounded corners", p.style.cornerRadius, 0f..0.2f, { v -> vm.setStyle { it.copy(cornerRadius = v) } }, vm::endLive) {
            if (it < 0.002f) "Square" else "${Math.round(it * 1000) / 10f}%"
        }
        LabeledSlider("Photo border", p.style.borderWidth, 0f..0.03f, { v -> vm.setStyle { it.copy(borderWidth = v) } }, vm::endLive) {
            if (it < 0.0005f) "None" else "${Math.round(it * 1000) / 10f}%"
        }
        if (p.style.borderWidth > 0f) ColorSwatches(p.style.borderColor, { c -> vm.setStyle(false) { it.copy(borderColor = c) } })

        SectionLabel("Background", Modifier.padding(top = 6.dp))
        ChipRow {
            SelectChip("Colour", p.background.type == BackgroundType.SOLID) { vm.setBackground(p.background.copy(type = BackgroundType.SOLID)) }
            SelectChip("Gradient", p.background.type == BackgroundType.GRADIENT) { vm.setBackground(p.background.copy(type = BackgroundType.GRADIENT, color2 = if (p.background.color2 == p.background.color1) 0xFFE8613C.toInt() else p.background.color2)) }
            TextureKind.values().forEach { t ->
                SelectChip(t.name.lowercase().replaceFirstChar { it.uppercase() }, p.background.type == BackgroundType.TEXTURE && p.background.texture == t) {
                    vm.setBackground(p.background.copy(type = BackgroundType.TEXTURE, texture = t, color2 = if (p.background.color1 == 0xFF1C1B1F.toInt() || p.background.color1 == 0xFF424242.toInt()) 0xFFFFFFFF.toInt() else 0xFF8A7A5A.toInt()))
                }
            }
            SelectChip("Transparent", p.background.type == BackgroundType.TRANSPARENT) { vm.setBackground(p.background.copy(type = BackgroundType.TRANSPARENT)) }
        }
        if (p.background.type != BackgroundType.TRANSPARENT) {
            SectionLabel(if (p.background.type == BackgroundType.GRADIENT || p.background.type == BackgroundType.TEXTURE) "Base colour" else "Colour")
            ColorSwatches(p.background.color1, { c -> vm.setBackground(p.background.copy(color1 = c)) })
            if (p.background.type == BackgroundType.GRADIENT) {
                SectionLabel("Second colour")
                ColorSwatches(p.background.color2, { c -> vm.setBackground(p.background.copy(color2 = c)) })
                LabeledSlider("Angle", p.background.angle, 0f..360f, { v -> vm.setBackground(p.background.copy(angle = v)) }, {}) { "${it.toInt()}°" }
            }
            if (p.background.type == BackgroundType.TEXTURE) {
                SectionLabel("Pattern colour")
                ColorSwatches(p.background.color2, { c -> vm.setBackground(p.background.copy(color2 = c)) })
            }
        } else {
            TinyLabel("Transparent backgrounds are kept when you export as PNG. JPEG uses white.")
        }
    }
}

private val FILTERS = listOf(
    FilterType.NONE to "Original", FilterType.BLACK_WHITE to "Black & white", FilterType.VINTAGE to "Vintage", FilterType.SEPIA to "Sepia",
    FilterType.FADE to "Fade", FilterType.VIVID to "Vivid", FilterType.WARM to "Warm", FilterType.COOL to "Cool",
)

@Composable
fun AdjustPanel(vm: CollageViewModel, p: CollageProject, selected: Int?) {
    var applyAll by remember { mutableStateOf(false) }
    val target = if (applyAll) null else selected
    val cell = (selected ?: p.cells.indexOfFirst { it.photo != null }.takeIf { it >= 0 })?.let { p.cells.getOrNull(it) }
    if (cell == null) { Text("Add a photo to start editing.", style = MaterialTheme.typography.bodyMedium); return }
    fun update(live: Boolean, f: (CellEdit) -> CellEdit) { if (target == null) vm.editAllCells(live, f) else vm.editCell(target, live, f) }
    val a = cell.adjustments
    Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(
                if (applyAll) "Editing all photos" else if (selected != null) "Editing photo ${selected + 1}" else "Tap a photo to edit it on its own",
                style = MaterialTheme.typography.labelLarge, modifier = Modifier.weight(1f),
            )
            Text("All photos", style = MaterialTheme.typography.labelMedium)
            Spacer(Modifier.width(8.dp))
            Switch(applyAll || selected == null, { applyAll = it }, enabled = selected != null)
        }
        ChipRow {
            FILTERS.forEach { (f, label) -> SelectChip(label, cell.filter == f) { update(false) { it.copy(filter = f) } } }
        }
        val end = vm::endLive
        LabeledSlider("Brightness", a.brightness, -1f..1f, { v -> update(true) { it.copy(adjustments = it.adjustments.copy(brightness = v)) } }, end)
        LabeledSlider("Contrast", a.contrast, -1f..1f, { v -> update(true) { it.copy(adjustments = it.adjustments.copy(contrast = v)) } }, end)
        LabeledSlider("Saturation", a.saturation, -1f..1f, { v -> update(true) { it.copy(adjustments = it.adjustments.copy(saturation = v)) } }, end)
        LabeledSlider("Warmth", a.warmth, -1f..1f, { v -> update(true) { it.copy(adjustments = it.adjustments.copy(warmth = v)) } }, end)
        LabeledSlider("Sharpness", a.sharpness, 0f..1f, { v -> update(true) { it.copy(adjustments = it.adjustments.copy(sharpness = v)) } }, end)
        TextButton({ update(false) { it.copy(adjustments = Adjustments(), filter = FilterType.NONE) } }) { Text("Reset adjustments") }
        TinyLabel("Edits are applied on top of your original photos. The originals are never changed.")
    }
}

private val FONT_SAMPLES = FontChoice.values().toList()

@Composable
fun TextPanel(vm: CollageViewModel, p: CollageProject, selectedText: Int?) {
    val t = selectedText?.let { p.texts.getOrNull(it) }
    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        ChipRow {
            Button({ vm.addText("Your text") }) { Text("＋ Add text") }
            OutlinedButton({ vm.addText(DateFormat.getDateInstance(DateFormat.LONG).format(Date())) }) { Text("📅 Today's date") }
            OutlinedButton({ vm.addText("Name") }) { Text("Name") }
            OutlinedButton({ vm.addText("Caption") }) { Text("Caption") }
        }
        if (p.texts.size > 1) {
            ChipRow {
                p.texts.forEachIndexed { i, x -> SelectChip(x.text.take(14).ifBlank { "Text ${i + 1}" }, i == selectedText) { vm.selectText(i) } }
            }
        }
        if (t == null || selectedText == null) {
            TinyLabel(if (p.texts.isEmpty()) "Add names, dates and captions. Drag text on the picture to move it." else "Tap text on the picture, or pick one above, to edit it.")
        } else {
            OutlinedTextField(t.text, { v -> vm.editText(selectedText, true) { it.copy(text = v.take(120)) } }, label = { Text("Text") }, modifier = Modifier.fillMaxWidth(), minLines = 1, maxLines = 3)
            SectionLabel("Font")
            ChipRow { FONT_SAMPLES.forEach { f -> SelectChip(f.label, t.font == f) { vm.editText(selectedText) { it.copy(font = f) } } } }
            LabeledSlider("Size", t.size, 0.02f..0.2f, { v -> vm.editText(selectedText, true) { it.copy(size = v) } }, vm::endLive) { "${Math.round(it * 100)}" }
            SectionLabel("Colour")
            ColorSwatches(t.color, { c -> vm.editText(selectedText) { it.copy(color = c) } })
            ChipRow {
                SelectChip("Bold", t.bold) { vm.editText(selectedText) { it.copy(bold = !it.bold) } }
                SelectChip("Italic", t.italic) { vm.editText(selectedText) { it.copy(italic = !it.italic) } }
                SelectChip("Shadow", t.shadow) { vm.editText(selectedText) { it.copy(shadow = !it.shadow) } }
                SelectChip("Label box", t.backgroundColor != 0) { vm.editText(selectedText) { it.copy(backgroundColor = if (it.backgroundColor == 0) 0x99000000.toInt() else 0) } }
                TextAlign.values().forEach { al -> SelectChip(al.name.lowercase().replaceFirstChar { it.uppercase() }, t.align == al) { vm.editText(selectedText) { it.copy(align = al) } } }
            }
            LabeledSlider("Tilt", t.rotation, -45f..45f, { v -> vm.editText(selectedText, true) { it.copy(rotation = v) } }, vm::endLive) { "${it.toInt()}°" }
            TextButton({ vm.deleteText(selectedText) }) { Text("Delete this text") }
        }
    }
}

@Composable
fun FacesPanel(vm: CollageViewModel, p: CollageProject, selected: Int?, facesPending: Int) {
    val analysed = p.cells.mapNotNull { it.photo }
    val found = analysed.count { !it.faces.isNullOrEmpty() }
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        SectionLabel("Automatic positioning")
        ChipRow {
            SelectChip("Centre only", p.faceMode == FaceMode.OFF) { vm.setFaceMode(FaceMode.OFF) }
            SelectChip("Keep faces in frame", p.faceMode == FaceMode.SMART) { vm.setFaceMode(FaceMode.SMART) }
            SelectChip("Align faces", p.faceMode == FaceMode.ALIGN) { vm.setFaceMode(FaceMode.ALIGN) }
        }
        Text(
            when (p.faceMode) {
                FaceMode.OFF -> "Photos are centred. Drag any photo to place it yourself."
                FaceMode.SMART -> "Each photo is centred on the people in it."
                FaceMode.ALIGN -> "Faces are matched in size and height so relatives line up. Photos are only scaled evenly, never stretched."
            },
            style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        Text(
            if (facesPending > 0) "Looking for faces on this device… ($facesPending left)"
            else if (p.faceMode != FaceMode.OFF && found == 0) "No faces found, so photos are centred. You can still drag and zoom each one."
            else "Faces found in $found of ${analysed.size} photos. Detection runs on your phone only.",
            style = MaterialTheme.typography.labelMedium,
        )
        Row(verticalAlignment = Alignment.CenterVertically) {
            Column(Modifier.weight(1f)) {
                Text("Never crop my photos", style = MaterialTheme.typography.labelLarge)
                TinyLabel("Show each whole photo, with bars instead of cropping")
            }
            Switch(analysed.isNotEmpty() && p.cells.filter { it.photo != null }.all { it.fit }, { vm.setAvoidCropping(it) })
        }
        TextButton({ vm.resetCrops() }) { Text("Redo automatic positioning for all photos") }

        val cell = selected?.let { p.cells.getOrNull(it) }
        if (cell?.photo != null) {
            SectionLabel(if (p.mode == ProjectMode.FAMILY) "About this person" else "Caption on this photo")
            val c = cell.caption
            OutlinedTextField(c.name, { v -> vm.editCell(selected, true) { it.copy(caption = it.caption.copy(name = v.take(24))) } }, label = { Text("Name") }, singleLine = true, modifier = Modifier.fillMaxWidth())
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                OutlinedTextField(c.relation, { v -> vm.editCell(selected, true) { it.copy(caption = it.caption.copy(relation = v.take(20))) } }, label = { Text("Relationship") }, singleLine = true, modifier = Modifier.weight(1f))
                OutlinedTextField(c.age, { v -> vm.editCell(selected, true) { it.copy(caption = it.caption.copy(age = v.take(10))) } }, label = { Text("Age") }, singleLine = true, modifier = Modifier.weight(0.6f))
            }
            TinyLabel("Captions appear along the bottom of the photo. Leave all blank for none.")
        } else {
            TinyLabel("Tap a photo to add a name, relationship and age caption.")
        }
    }
}
