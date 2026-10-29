package com.mundymorning.touchgesture

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Surface
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

/** Text that tells the user, in words, what one finger will do right now. */
fun TouchMode.instruction(hasTarget: Boolean = true): String = when {
    !hasTarget -> "Tap a photo to choose it"
    this == TouchMode.PAN -> "PAN: drag one finger to move the photo"
    else -> "ZOOM: slide one finger up to zoom in, down to zoom out"
}

val TouchMode.label: String get() = if (this == TouchMode.PAN) "PAN" else "ZOOM"
val TouchMode.glyph: String get() = if (this == TouchMode.PAN) "✥" else "⇕"

/**
 * The Touch Gesture Standard control strip: PAN and ZOOM mode buttons, RESET, and a banner that always states what
 * one finger does. Every target is at least 56dp high.
 */
@Composable
fun GestureModeBar(
    mode: TouchMode,
    onModeChange: (TouchMode) -> Unit,
    onReset: () -> Unit,
    hasTarget: Boolean,
    onHelp: () -> Unit,
    modifier: Modifier = Modifier,
    zoomLabel: String? = null,
) {
    Column(modifier.fillMaxWidth().padding(horizontal = 12.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
            TouchMode.values().forEach { m ->
                val sel = m == mode
                val desc = if (m == TouchMode.PAN) "Pan mode. One finger drags the selected photo." else "Zoom mode. One finger slides up to zoom in and down to zoom out."
                val colors = if (sel) ButtonDefaults.buttonColors() else ButtonDefaults.outlinedButtonColors()
                val content: @Composable () -> Unit = { ModeLabel(m.glyph, m.label) }
                val mod = Modifier.weight(1f).heightIn(min = 56.dp).semantics {
                    role = Role.RadioButton; selected = sel; contentDescription = desc
                }
                if (sel) Button({ onModeChange(m) }, mod, colors = colors, shape = RoundedCornerShape(16.dp), contentPadding = TightPadding) { content() }
                else OutlinedButton({ onModeChange(m) }, mod, shape = RoundedCornerShape(16.dp), contentPadding = TightPadding) { content() }
            }
            OutlinedButton(
                onReset, Modifier.weight(1f).heightIn(min = 56.dp).semantics { contentDescription = "Reset the selected photo to its automatic position and zoom" },
                enabled = hasTarget, shape = RoundedCornerShape(16.dp), contentPadding = TightPadding,
            ) { ModeLabel("↺", "RESET") }
            TextButton(onHelp, Modifier.size(56.dp).semantics { contentDescription = "How the touch controls work" }) { Text("?", fontSize = 22.sp, fontWeight = FontWeight.Bold) }
        }
        Surface(
            color = if (hasTarget) MaterialTheme.colorScheme.primaryContainer else MaterialTheme.colorScheme.surfaceVariant,
            contentColor = if (hasTarget) MaterialTheme.colorScheme.onPrimaryContainer else MaterialTheme.colorScheme.onSurfaceVariant,
            shape = RoundedCornerShape(12.dp),
            modifier = Modifier.fillMaxWidth().semantics { liveRegion = LiveRegionMode.Polite },
        ) {
            Row(Modifier.padding(horizontal = 12.dp, vertical = 8.dp), verticalAlignment = Alignment.CenterVertically) {
                Text(mode.instruction(hasTarget), fontWeight = FontWeight.SemiBold, fontSize = 14.sp, modifier = Modifier.weight(1f))
                if (zoomLabel != null && hasTarget) Text(zoomLabel, fontWeight = FontWeight.Bold, fontSize = 14.sp)
            }
        }
    }
}

private val TightPadding = androidx.compose.foundation.layout.PaddingValues(horizontal = 2.dp, vertical = 4.dp)

/** Icon over label, never wraps: stays readable on the narrowest phones. */
@Composable
private fun ModeLabel(glyph: String, label: String) {
    Column(horizontalAlignment = Alignment.CenterHorizontally) {
        Text(glyph, fontSize = 20.sp, lineHeight = 22.sp, maxLines = 1, softWrap = false)
        Text(label, fontWeight = FontWeight.Bold, fontSize = 13.sp, lineHeight = 15.sp, maxLines = 1, softWrap = false)
    }
}

/** Short first-use explanation, with the pinch preference. */
@Composable
fun GestureIntroDialog(pinchEnabled: Boolean, onPinchChange: (Boolean) -> Unit, onDismiss: () -> Unit) {
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("Move and zoom with one finger") },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                Text("1. Tap a photo to choose it.")
                Text("2. Pick PAN or ZOOM under the picture. The bar always tells you what your finger will do.")
                Text("3. PAN: drag one finger anywhere to move the photo.")
                Text("4. ZOOM: slide one finger up to zoom in, down to zoom out. Tiny movements make tiny changes.")
                Text("5. RESET puts the photo back where the app first placed it.")
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Column(Modifier.weight(1f)) {
                        Text("Also allow two-finger pinch", fontWeight = FontWeight.SemiBold)
                        Text("You can change this any time with the ? button.", fontSize = 12.sp)
                    }
                    Switch(pinchEnabled, onPinchChange)
                }
            }
        },
        confirmButton = { Button(onDismiss, Modifier.heightIn(min = 56.dp)) { Text("Got it") } },
    )
}
