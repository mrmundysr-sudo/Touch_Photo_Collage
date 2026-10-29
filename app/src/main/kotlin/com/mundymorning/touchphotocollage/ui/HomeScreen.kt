package com.mundymorning.touchphotocollage.ui

import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.scale
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.mundymorning.collage.engine.project.ProjectMode
import com.mundymorning.collage.engine.project.ProjectSummary
import com.mundymorning.collage.engine.project.SavedTemplate
import com.mundymorning.touchphotocollage.HomeData

@OptIn(ExperimentalFoundationApi::class)
@Composable
fun HomeScreen(
    data: HomeData,
    theme: ThemeMode,
    onTheme: (ThemeMode) -> Unit,
    onCreate: (ProjectMode) -> Unit,
    onOpen: (String) -> Unit,
    onDelete: (String) -> Unit,
    onTemplate: (SavedTemplate) -> Unit,
    onDeleteTemplate: (String) -> Unit,
) {
    var confirmDelete by remember { mutableStateOf<ProjectSummary?>(null) }
    var confirmDeleteTemplate by remember { mutableStateOf<SavedTemplate?>(null) }
    var menu by remember { mutableStateOf(false) }

    Column(
        Modifier.fillMaxSize().background(MaterialTheme.colorScheme.background).statusBarsPadding().navigationBarsPadding()
            .verticalScroll(rememberScrollState()).padding(horizontal = 16.dp),
    ) {
        Row(Modifier.fillMaxWidth().padding(top = 12.dp), verticalAlignment = Alignment.CenterVertically) {
            Column(Modifier.weight(1f)) {
                Text("Touch", style = MaterialTheme.typography.labelLarge, color = MaterialTheme.colorScheme.primary)
                Text("Photo Collage", style = MaterialTheme.typography.headlineLarge)
            }
            Box {
                IconButton({ menu = true }, Modifier.size(48.dp)) { Icon(Icons.Filled.Settings, "Appearance settings") }
                DropdownMenu(menu, { menu = false }) {
                    listOf(ThemeMode.SYSTEM to "Match system", ThemeMode.LIGHT to "Light", ThemeMode.DARK to "Dark").forEach { (m, label) ->
                        DropdownMenuItem(text = { Text(if (m == theme) "✓  $label" else "    $label") }, onClick = { onTheme(m); menu = false })
                    }
                }
            }
        }

        Spacer(Modifier.height(16.dp))
        Hero(onClick = { onCreate(ProjectMode.COLLAGE) })

        Spacer(Modifier.height(16.dp))
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            QuickTile("Side by side", "Compare two photos", Teal, Modifier.weight(1f), TileIcon.SIDE) { onCreate(ProjectMode.COMPARE) }
            QuickTile("Family", "Resemblance mode", Violet, Modifier.weight(1f), TileIcon.FACES) { onCreate(ProjectMode.FAMILY) }
            QuickTile("Photo grid", "Neat equal tiles", Sunny, Modifier.weight(1f), TileIcon.GRID) { onCreate(ProjectMode.GRID) }
        }

        Spacer(Modifier.height(24.dp))
        Text("Recent projects", style = MaterialTheme.typography.titleLarge)
        Spacer(Modifier.height(8.dp))
        if (data.recents.isEmpty()) {
            EmptyCard("Your collages will appear here", "Tap “Create Collage” to make your first one. It takes about ten seconds.")
        } else {
            LazyRow(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                items(data.recents, key = { it.id }) { p ->
                    RecentCard(p, onClick = { onOpen(p.id) }, onLongClick = { confirmDelete = p })
                }
            }
            TinyLabel("Press and hold a project to delete it")
        }

        Spacer(Modifier.height(24.dp))
        Text("Saved templates", style = MaterialTheme.typography.titleLarge)
        Spacer(Modifier.height(8.dp))
        if (data.templates.isEmpty()) {
            EmptyCard("No templates yet", "In the editor, choose Layout → Save as template to reuse a look with new photos.")
        } else {
            LazyRow(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                items(data.templates, key = { it.id }) { t ->
                    TemplateCard(t, onClick = { onTemplate(t) }, onLongClick = { confirmDeleteTemplate = t })
                }
            }
        }

        Spacer(Modifier.height(24.dp))
        Row(
            Modifier.fillMaxWidth().clip(RoundedCornerShape(16.dp)).background(MaterialTheme.colorScheme.surfaceContainer).padding(14.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text("🔒", fontSize = 20.sp)
            Spacer(Modifier.width(10.dp))
            Text(
                "Private by design. Everything works offline and your photos never leave this phone unless you save or share.",
                style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
        Spacer(Modifier.height(24.dp))
    }

    confirmDelete?.let { p ->
        AlertDialog(
            onDismissRequest = { confirmDelete = null },
            title = { Text("Delete “${p.name}”?") },
            text = { Text("The project and its private photo copies are removed from this app. Your original photos are not touched.") },
            confirmButton = { TextButton({ onDelete(p.id); confirmDelete = null }) { Text("Delete") } },
            dismissButton = { TextButton({ confirmDelete = null }) { Text("Keep") } },
        )
    }
    confirmDeleteTemplate?.let { t ->
        AlertDialog(
            onDismissRequest = { confirmDeleteTemplate = null },
            title = { Text("Delete template “${t.name}”?") },
            confirmButton = { TextButton({ onDeleteTemplate(t.id); confirmDeleteTemplate = null }) { Text("Delete") } },
            dismissButton = { TextButton({ confirmDeleteTemplate = null }) { Text("Keep") } },
        )
    }
}

@Composable
private fun Hero(onClick: () -> Unit) {
    val pulse = rememberInfiniteTransition(label = "pulse").animateFloat(
        1f, 1.035f, infiniteRepeatable(tween(1400), RepeatMode.Reverse), label = "scale",
    )
    Box(
        Modifier.fillMaxWidth().clip(RoundedCornerShape(28.dp))
            .background(Brush.linearGradient(listOf(Color(0xFF3A2A66), Color(0xFF7B3F8F), Color(0xFFD9573C))))
            .padding(20.dp),
    ) {
        Column {
            HeroMosaic(Modifier.fillMaxWidth().height(110.dp))
            Spacer(Modifier.height(16.dp))
            Text("Turn your photos into one beautiful picture", style = MaterialTheme.typography.titleLarge, color = Color.White)
            Spacer(Modifier.height(4.dp))
            Text("Pick photos, we arrange them, you save or share.", style = MaterialTheme.typography.bodyMedium, color = Color.White.copy(alpha = 0.85f))
            Spacer(Modifier.height(16.dp))
            Box(
                Modifier.fillMaxWidth().height(64.dp).scale(pulse.value).clip(RoundedCornerShape(20.dp)).background(Color.White)
                    .clickable(onClickLabel = "Create a collage", onClick = onClick),
                contentAlignment = Alignment.Center,
            ) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Icon(Icons.Filled.Add, null, tint = Color(0xFF7B2D1A))
                    Spacer(Modifier.width(8.dp))
                    Text("Create Collage", fontSize = 20.sp, fontWeight = FontWeight.Bold, color = Color(0xFF7B2D1A))
                }
            }
        }
    }
}

@Composable
private fun HeroMosaic(modifier: Modifier) {
    val colors = listOf(Coral, Sunny, Teal, Violet, Color(0xFFE46A9B))
    Canvas(modifier) {
        val g = 6.dp.toPx(); val r = CornerRadius(12.dp.toPx())
        val w = size.width; val h = size.height
        fun cell(i: Int, l: Float, t: Float, rr: Float, b: Float) = drawRoundRect(
            colors[i % colors.size].copy(alpha = 0.95f), Offset(l * w + g / 2, t * h + g / 2), Size((rr - l) * w - g, (b - t) * h - g), r,
        )
        cell(0, 0f, 0f, 0.34f, 1f); cell(1, 0.34f, 0f, 0.68f, 0.55f); cell(2, 0.34f, 0.55f, 0.68f, 1f)
        cell(3, 0.68f, 0f, 1f, 0.4f); cell(4, 0.68f, 0.4f, 1f, 1f)
    }
}

private enum class TileIcon { SIDE, FACES, GRID }

@Composable
private fun QuickTile(title: String, subtitle: String, accent: Color, modifier: Modifier, icon: TileIcon, onClick: () -> Unit) {
    Column(
        modifier.clip(RoundedCornerShape(20.dp)).background(MaterialTheme.colorScheme.surfaceContainer).clickable(onClick = onClick)
            .padding(12.dp).semantics { contentDescription = "$title. $subtitle" },
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Canvas(Modifier.size(52.dp)) {
            val r = CornerRadius(8.dp.toPx())
            when (icon) {
                TileIcon.SIDE -> {
                    drawRoundRect(accent, Offset(0f, 4.dp.toPx()), Size(size.width / 2 - 2.dp.toPx(), size.height - 8.dp.toPx()), r)
                    drawRoundRect(accent.copy(alpha = 0.6f), Offset(size.width / 2 + 2.dp.toPx(), 4.dp.toPx()), Size(size.width / 2 - 2.dp.toPx(), size.height - 8.dp.toPx()), r)
                }
                TileIcon.FACES -> {
                    val rad = size.width * 0.17f
                    listOf(0.28f to 0.55f, 0.72f to 0.45f).forEachIndexed { i, (x, y) ->
                        drawCircle(accent.copy(alpha = if (i == 0) 1f else 0.6f), rad, Offset(size.width * x, size.height * (y - 0.12f)))
                        drawRoundRect(accent.copy(alpha = if (i == 0) 1f else 0.6f), Offset(size.width * x - rad * 1.4f, size.height * (y + 0.1f)), Size(rad * 2.8f, size.height * 0.34f), CornerRadius(rad))
                    }
                }
                TileIcon.GRID -> {
                    val c = size.width / 2 - 2.dp.toPx()
                    for (i in 0..1) for (j in 0..1)
                        drawRoundRect(accent.copy(alpha = if ((i + j) % 2 == 0) 1f else 0.6f), Offset(i * (c + 4.dp.toPx()), j * (c + 4.dp.toPx())), Size(c, c), CornerRadius(6.dp.toPx()))
                }
            }
        }
        Spacer(Modifier.height(8.dp))
        Text(title, style = MaterialTheme.typography.labelLarge, textAlign = TextAlign.Center, maxLines = 1)
        Text(subtitle, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant, textAlign = TextAlign.Center, maxLines = 2)
    }
}

@Composable
private fun EmptyCard(title: String, body: String) {
    Column(
        Modifier.fillMaxWidth().clip(RoundedCornerShape(20.dp)).border(1.dp, MaterialTheme.colorScheme.outlineVariant, RoundedCornerShape(20.dp)).padding(18.dp),
    ) {
        Text(title, style = MaterialTheme.typography.titleMedium)
        Spacer(Modifier.height(4.dp))
        Text(body, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun RecentCard(p: ProjectSummary, onClick: () -> Unit, onLongClick: () -> Unit) {
    val bmp = remember(p.id, p.updatedAt) { p.thumb?.let { runCatching { android.graphics.BitmapFactory.decodeFile(it.path) }.getOrNull() } }
    Column(
        Modifier.width(140.dp).clip(RoundedCornerShape(16.dp)).combinedClickable(onClick = onClick, onLongClick = onLongClick)
            .semantics { contentDescription = "Open project ${p.name}" },
    ) {
        Box(Modifier.fillMaxWidth().height(140.dp).clip(RoundedCornerShape(16.dp)).background(MaterialTheme.colorScheme.surfaceVariant), contentAlignment = Alignment.Center) {
            if (bmp != null) Image(bmp.asImageBitmap(), p.name, contentScale = ContentScale.Fit, modifier = Modifier.fillMaxSize().padding(2.dp))
            else Text("🖼", fontSize = 32.sp)
        }
        Spacer(Modifier.height(6.dp))
        Text(p.name, style = MaterialTheme.typography.labelLarge, maxLines = 1, overflow = TextOverflow.Ellipsis)
        TinyLabel("${p.photoCount} photo${if (p.photoCount == 1) "" else "s"}")
    }
}

@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun TemplateCard(t: SavedTemplate, onClick: () -> Unit, onLongClick: () -> Unit) {
    Column(
        Modifier.width(110.dp).clip(RoundedCornerShape(16.dp)).combinedClickable(onClick = onClick, onLongClick = onLongClick)
            .background(MaterialTheme.colorScheme.surfaceContainer).padding(10.dp).semantics { contentDescription = "Use template ${t.name}" },
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Box(Modifier.size(80.dp), contentAlignment = Alignment.Center) {
            LayoutThumb(t.layout, t.canvas.aspect, selected = false, onClick = onClick, label = "")
        }
        Text(t.name, style = MaterialTheme.typography.labelLarge, maxLines = 1, overflow = TextOverflow.Ellipsis)
        TinyLabel("${t.layout.count} photos")
    }
}
