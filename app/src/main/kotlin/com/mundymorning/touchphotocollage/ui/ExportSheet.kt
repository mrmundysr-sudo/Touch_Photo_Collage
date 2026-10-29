package com.mundymorning.touchphotocollage.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Button
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.mundymorning.collage.engine.export.ExportFormat
import com.mundymorning.collage.engine.export.ExportQuality
import com.mundymorning.collage.engine.export.ExportRequest
import com.mundymorning.collage.engine.project.BackgroundType
import com.mundymorning.collage.engine.project.CollageProject

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ExportSheet(
    project: CollageProject,
    sizeFor: (ExportQuality) -> Pair<Int, Int>,
    onDismiss: () -> Unit,
    onSave: (ExportRequest) -> Unit,
    onShare: (ExportRequest) -> Unit,
) {
    var format by remember { mutableStateOf(ExportFormat.JPEG) }
    var quality by remember { mutableStateOf(ExportQuality.STANDARD) }
    var transparent by remember { mutableStateOf(project.background.type == BackgroundType.TRANSPARENT) }
    val (w, h) = sizeFor(quality)
    val req = ExportRequest(format, quality, transparent && format == ExportFormat.PNG)
    ModalBottomSheet(onDismissRequest = onDismiss) {
        Column(Modifier.fillMaxWidth().padding(horizontal = 20.dp).padding(bottom = 16.dp).navigationBarsPadding(), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Text("Save or share", style = MaterialTheme.typography.titleLarge)
            SectionLabel("Format")
            ChipRow {
                SelectChip("JPEG · small file", format == ExportFormat.JPEG) { format = ExportFormat.JPEG }
                SelectChip("PNG · lossless", format == ExportFormat.PNG) { format = ExportFormat.PNG }
            }
            SectionLabel("Quality")
            ChipRow {
                ExportQuality.values().forEach { q ->
                    val (qw, qh) = sizeFor(q)
                    SelectChip("${q.label} · $qw × $qh", quality == q) { quality = q }
                }
            }
            Text("$w × $h pixels · ${if (format == ExportFormat.JPEG) "JPEG ${quality.jpegQuality}%" else "PNG"}", style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
            if (format == ExportFormat.PNG) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Column(Modifier.weight(1f)) {
                        Text("Transparent background", style = MaterialTheme.typography.labelLarge)
                        Text("Gaps and margins become see-through", style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                    Switch(transparent, { transparent = it })
                }
            }
            Spacer(Modifier.height(4.dp))
            Button({ onSave(req) }, Modifier.fillMaxWidth().height(52.dp)) { Text("Save to Gallery") }
            OutlinedButton({ onShare(req) }, Modifier.fillMaxWidth().height(52.dp)) { Text("Share…") }
            Text(
                "Your collage is rendered once from your original photos at full resolution, then encoded a single time, so it is never recompressed.",
                style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}
