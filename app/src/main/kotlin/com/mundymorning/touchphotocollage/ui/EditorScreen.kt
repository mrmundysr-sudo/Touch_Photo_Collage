package com.mundymorning.touchphotocollage.ui

import androidx.activity.compose.BackHandler
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.animateContentSize
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.mundymorning.collage.engine.project.ProjectMode
import com.mundymorning.touchgesture.GestureIntroDialog
import com.mundymorning.touchgesture.GestureModeBar
import com.mundymorning.touchgesture.glyph
import com.mundymorning.touchgesture.label
import com.mundymorning.touchphotocollage.CollageViewModel

private enum class Tab(val label: String, val glyph: String) {
    LAYOUT("Layout", "▦"), STYLE("Style", "◐"), ADJUST("Adjust", "☼"), TEXT("Text", "Aa"), FACES("Faces", "☺")
}

@Composable
fun EditorScreen(vm: CollageViewModel, onExport: () -> Unit) {
    val project by vm.project.collectAsState()
    val frame by vm.preview.collectAsState()
    val selection by vm.selection.collectAsState()
    val canUndo by vm.canUndo.collectAsState()
    val canRedo by vm.canRedo.collectAsState()
    val canvasPx by vm.canvasPx.collectAsState()
    val facesPending by vm.facesPending.collectAsState()
    val touchMode by vm.touchMode.collectAsState()
    val pinch by vm.pinchEnabled.collectAsState()
    val introSeen by vm.introSeen.collectAsState()
    val sensitivity by vm.zoomSensitivity.collectAsState()
    val frameTiming by vm.frameTiming.collectAsState()
    val live = vm.live
    var help by remember { mutableStateOf(false) }
    val p = project ?: return

    var tab by rememberSaveable { mutableStateOf(if (p.mode == ProjectMode.FAMILY) Tab.FACES else Tab.LAYOUT) }
    var panelOpen by rememberSaveable { mutableStateOf(true) }
    var renaming by remember { mutableStateOf(false) }
    var confirmExit by remember { mutableStateOf(false) }

    val replace = rememberLauncherForActivityResult(ActivityResultContracts.PickVisualMedia()) { uri ->
        val i = selection.cell
        if (uri != null && i != null) vm.replacePhoto(i, uri)
    }
    val add = rememberLauncherForActivityResult(ActivityResultContracts.PickMultipleVisualMedia(20)) { uris -> vm.addPhotos(uris) }

    BackHandler { vm.closeEditor() }

    Column(Modifier.fillMaxSize().background(MaterialTheme.colorScheme.background).statusBarsPadding().navigationBarsPadding().imePadding()) {
        // ---- top bar
        Row(Modifier.fillMaxWidth().padding(horizontal = 4.dp), verticalAlignment = Alignment.CenterVertically) {
            IconButton({ vm.closeEditor() }, Modifier.size(48.dp)) { Icon(Icons.AutoMirrored.Filled.ArrowBack, "Back to home") }
            Text(
                p.name, style = MaterialTheme.typography.titleMedium, maxLines = 1, overflow = TextOverflow.Ellipsis,
                modifier = Modifier.weight(1f).clip(RoundedCornerShape(8.dp)).clickable { renaming = true }.padding(8.dp)
                    .semantics { contentDescription = "Project name ${p.name}. Tap to rename." },
            )
            GlyphButton("↶", "Undo", canUndo) { vm.undo() }
            GlyphButton("↷", "Redo", canRedo) { vm.redo() }
            Spacer(Modifier.width(4.dp))
            Button(onExport, contentPadding = androidx.compose.foundation.layout.PaddingValues(horizontal = 16.dp)) { Text("Save") }
            Spacer(Modifier.width(8.dp))
        }

        // ---- canvas
        BoxWithConstraints(Modifier.weight(1f).fillMaxWidth().padding(horizontal = 12.dp, vertical = 6.dp), contentAlignment = Alignment.Center) {
            val density = LocalDensity.current
            val wPx = with(density) { maxWidth.roundToPx() }
            val hPx = with(density) { maxHeight.roundToPx() }
            LaunchedEffect(wPx, hPx) { vm.setViewport(wPx, hPx) }
            val (cw, ch) = canvasPx
            if (cw > 0 && ch > 0) {
                Box(Modifier.shadow(6.dp, RoundedCornerShape(4.dp))) {
                    CollageCanvas(
                        project = p, frame = frame, widthPx = cw, heightPx = ch, selection = selection,
                        onSelectCell = vm::selectCell, onSelectText = vm::selectText,
                        onTransform = { i, px, py, z, fx, fy, w, h -> vm.transformCell(i, px, py, z, fx, fy, w, h) },
                        onMoveText = vm::moveText, onSwap = vm::swapCells, onGestureEnd = vm::endLive,
                        mode = touchMode, pinchEnabled = pinch,
                        onZoomStep = { f -> selection.cell?.let { vm.stepCell(it, 0f, 0f, f) } },
                        onPanStep = { dx, dy -> selection.cell?.let { vm.stepCell(it, dx, dy, 1f) } },
                        onReset = { selection.cell?.let { vm.resetCell(it) } },
                        live = live, renderer = vm.liveRenderer, liveBitmap = vm::liveBitmap, onCommit = vm::commitCrop, sensitivity = sensitivity,
                    )
                }
            }
            val selCell = selection.cell?.let { p.cells.getOrNull(it) }?.takeIf { it.photo != null }
            if (selCell != null) {
                ModeBadge(Modifier.align(Alignment.TopStart), touchMode, live, selection.cell ?: -1, selCell.zoom)
            }
            if (frameTiming) com.mundymorning.touchgesture.FrameTimingOverlay(Modifier.align(Alignment.BottomCenter))
            if (facesPending > 0) {
                Text(
                    "Finding faces…", style = MaterialTheme.typography.labelMedium,
                    modifier = Modifier.align(Alignment.TopCenter).clip(RoundedCornerShape(50)).background(MaterialTheme.colorScheme.secondaryContainer).padding(horizontal = 12.dp, vertical = 4.dp),
                    color = MaterialTheme.colorScheme.onSecondaryContainer,
                )
            }
        }

        // ---- one-finger controls (Touch Gesture Standard)
        val selectedCell = selection.cell?.let { p.cells.getOrNull(it) }?.takeIf { it.photo != null }
        GestureModeBar(
            mode = touchMode, onModeChange = vm::setTouchMode, onReset = { selection.cell?.let { vm.resetCell(it) } },
            hasTarget = selectedCell != null, onHelp = { help = true },
            zoomLabel = { selectedCell?.let { c -> "×${"%.1f".format(if (live.active && live.index == selection.cell) live.zoom else c.zoom)}" } },
        )
        Spacer(Modifier.height(4.dp))

        // ---- selected photo tools
        AnimatedVisibility(selection.cell != null && p.cells.getOrNull(selection.cell ?: -1)?.photo != null, enter = fadeIn() + slideInVertically { it / 2 }, exit = fadeOut() + slideOutVertically { it / 2 }) {
            val i = selection.cell ?: 0
            val cell = p.cells.getOrNull(i)
            ChipRow(Modifier.fillMaxWidth().padding(horizontal = 12.dp, vertical = 4.dp)) {
                ToolChip("⟳", "Rotate") { vm.rotateCell(i) }
                ToolChip("⇋", "Mirror") { vm.mirrorCell(i) }
                ToolChip(if (cell?.fit == true) "⤢" else "⛶", if (cell?.fit == true) "Fill" else "Fit whole") { vm.toggleFit(i) }
                ToolChip("◎", "Reset crop") { vm.resetCell(i) }
                ToolChip("🖼", "Replace") { replace.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly)) }
                if (i > 0) ToolChip("◀", "Move earlier") { vm.moveCell(i, -1) }
                if (i < p.cells.size - 1) ToolChip("▶", "Move later") { vm.moveCell(i, 1) }
                if (p.photoCount > 1) ToolChip("✕", "Remove") { vm.removeCell(i) }
            }
        }

        // ---- tabs + panel
        Column(
            Modifier.fillMaxWidth().clip(RoundedCornerShape(topStart = 24.dp, topEnd = 24.dp)).background(MaterialTheme.colorScheme.surfaceContainer).animateContentSize(),
        ) {
            Row(Modifier.fillMaxWidth().padding(horizontal = 6.dp, vertical = 4.dp), horizontalArrangement = Arrangement.SpaceEvenly) {
                Tab.values().forEach { t ->
                    val sel = t == tab && panelOpen
                    Column(
                        Modifier.weight(1f).clip(RoundedCornerShape(14.dp)).clickable {
                            if (t == tab) panelOpen = !panelOpen else { tab = t; panelOpen = true }
                        }.background(if (sel) MaterialTheme.colorScheme.primaryContainer else androidx.compose.ui.graphics.Color.Transparent)
                            .padding(vertical = 6.dp).semantics { contentDescription = "${t.label} tab" },
                        horizontalAlignment = Alignment.CenterHorizontally,
                    ) {
                        Text(t.glyph, style = MaterialTheme.typography.titleMedium, color = if (sel) MaterialTheme.colorScheme.onPrimaryContainer else MaterialTheme.colorScheme.onSurfaceVariant)
                        Text(t.label, style = MaterialTheme.typography.labelSmall, color = if (sel) MaterialTheme.colorScheme.onPrimaryContainer else MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                }
            }
            if (panelOpen) {
                Column(Modifier.fillMaxWidth().heightIn(max = 200.dp).verticalScroll(rememberScrollState()).padding(horizontal = 16.dp, vertical = 8.dp)) {
                    when (tab) {
                        Tab.LAYOUT -> {
                            LayoutPanel(vm, p)
                            TextButton({ add.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly)) }) { Text("＋ Add more photos") }
                        }
                        Tab.STYLE -> StylePanel(vm, p)
                        Tab.ADJUST -> AdjustPanel(vm, p, selection.cell)
                        Tab.TEXT -> TextPanel(vm, p, selection.text)
                        Tab.FACES -> FacesPanel(vm, p, selection.cell, facesPending)
                    }
                }
            }
        }
    }

    if (!introSeen || help) {
        GestureIntroDialog(pinch, vm::setPinchEnabled, sensitivity, vm::setZoomSensitivity, frameTiming, vm::setFrameTiming) { vm.markIntroSeen(); help = false }
    }

    if (renaming) {
        var name by remember { mutableStateOf(p.name) }
        AlertDialog(
            onDismissRequest = { renaming = false },
            title = { Text("Rename project") },
            text = { OutlinedTextField(name, { name = it.take(40) }, singleLine = true) },
            confirmButton = { TextButton({ vm.rename(name); renaming = false }) { Text("Rename") } },
            dismissButton = { TextButton({ renaming = false }) { Text("Cancel") } },
        )
    }
}

/** Reads the live zoom itself, so per-frame zoom changes recompose only this badge. */
@Composable
private fun ModeBadge(modifier: Modifier, mode: com.mundymorning.touchgesture.TouchMode, live: com.mundymorning.touchphotocollage.LiveGesture, cell: Int, committedZoom: Float) {
    val z = if (live.active && live.index == cell) live.zoom else committedZoom
    Text(
        "${mode.glyph} ${mode.label}  ×${"%.1f".format(z)}", style = MaterialTheme.typography.labelLarge,
        modifier = modifier.clip(RoundedCornerShape(50)).background(MaterialTheme.colorScheme.primary).padding(horizontal = 12.dp, vertical = 6.dp),
        color = MaterialTheme.colorScheme.onPrimary,
    )
}

@Composable
private fun GlyphButton(glyph: String, label: String, enabled: Boolean, onClick: () -> Unit) {
    IconButton(onClick, Modifier.size(48.dp), enabled = enabled) {
        Text(glyph, style = MaterialTheme.typography.titleLarge, color = if (enabled) MaterialTheme.colorScheme.onSurface else MaterialTheme.colorScheme.outlineVariant,
            modifier = Modifier.semantics { contentDescription = label })
    }
}

@Composable
private fun ToolChip(glyph: String, label: String, onClick: () -> Unit) {
    androidx.compose.material3.AssistChip(onClick = onClick, label = { Text(label) }, leadingIcon = { Text(glyph) })
}
