package com.mundymorning.touchphotocollage

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.activity.viewModels
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.SnackbarResult
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import kotlinx.coroutines.launch
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import com.mundymorning.collage.engine.export.ExportRequest
import com.mundymorning.collage.engine.project.ProjectMode
import com.mundymorning.collage.engine.project.SavedTemplate
import com.mundymorning.touchphotocollage.ui.AppTheme
import com.mundymorning.touchphotocollage.ui.EditorScreen
import com.mundymorning.touchphotocollage.ui.ExportSheet
import com.mundymorning.touchphotocollage.ui.HomeScreen
import com.mundymorning.touchphotocollage.ui.SelectChip
import com.mundymorning.touchphotocollage.ui.ChipRow

class MainActivity : ComponentActivity() {
    private val vm: CollageViewModel by viewModels()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        setContent {
            val theme by vm.theme.collectAsState()
            AppTheme(theme) { AppRoot(vm) }
        }
    }
}

private fun maxPick(limit: Int): Int = try {
    minOf(limit, if (android.os.Build.VERSION.SDK_INT >= 33 || android.os.ext.SdkExtensions.getExtensionVersion(Build.VERSION_CODES.R) >= 2) android.provider.MediaStore.getPickImagesMaxLimit() else limit)
} catch (t: Throwable) { limit }

@Composable
private fun AppRoot(vm: CollageViewModel) {
    val ctx = LocalContext.current
    val screen by vm.screen.collectAsState()
    val home by vm.home.collectAsState()
    val theme by vm.theme.collectAsState()
    val busy by vm.busy.collectAsState()
    val project by vm.project.collectAsState()
    val snackbar = remember { SnackbarHostState() }
    val scope = rememberCoroutineScope()
    var exporting by remember { mutableStateOf(false) }
    var pendingMode by remember { mutableStateOf(ProjectMode.COLLAGE) }
    var pendingTemplate by remember { mutableStateOf<SavedTemplate?>(null) }
    var gridUris by remember { mutableStateOf<List<Uri>?>(null) }
    var pendingExport by remember { mutableStateOf<Pair<ExportRequest, Boolean>?>(null) }

    fun handle(uris: List<Uri>) {
        val t = pendingTemplate
        pendingTemplate = null
        when {
            uris.isEmpty() -> Unit
            t != null -> vm.startFromTemplate(t, uris)
            pendingMode == ProjectMode.GRID -> gridUris = uris
            else -> vm.startNew(pendingMode, uris)
        }
    }

    val pick30 = rememberLauncherForActivityResult(ActivityResultContracts.PickMultipleVisualMedia(maxPick(30))) { handle(it) }
    val pick2 = rememberLauncherForActivityResult(ActivityResultContracts.PickMultipleVisualMedia(2)) { handle(it) }
    val pick8 = rememberLauncherForActivityResult(ActivityResultContracts.PickMultipleVisualMedia(maxPick(8))) { handle(it) }
    val imageOnly = PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly)

    val storagePermission = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
        val pe = pendingExport
        pendingExport = null
        if (granted && pe != null) vm.export(pe.first, share = false)
        else if (pe != null) scope.launch { snackbar.showSnackbar("Allow storage access to save to your gallery, or use Share instead.") }
    }

    LaunchedEffect(Unit) {
        vm.events.collect { e ->
            when (e) {
                is UiEvent.Message -> snackbar.showSnackbar(e.text)
                is UiEvent.Saved -> {
                    exporting = false
                    val r = snackbar.showSnackbar("Saved to ${e.where}", actionLabel = "View")
                    if (r == SnackbarResult.ActionPerformed) {
                        runCatching { ctx.startActivity(Intent(Intent.ACTION_VIEW).setDataAndType(e.uri, "image/*").addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)) }
                    }
                }
                is UiEvent.Share -> {
                    exporting = false
                    val send = Intent(Intent.ACTION_SEND).apply {
                        type = e.mime; putExtra(Intent.EXTRA_STREAM, e.uri); addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                        clipData = android.content.ClipData.newRawUri("collage", e.uri)
                    }
                    runCatching { ctx.startActivity(Intent.createChooser(send, "Share collage")) }
                }
            }
        }
    }

    Box(Modifier.fillMaxSize().background(MaterialTheme.colorScheme.background)) {
        AnimatedContent(
            screen,
            transitionSpec = {
                if (targetState == Screen.EDITOR) (slideInVertically { it / 12 } + fadeIn()) togetherWith fadeOut()
                else fadeIn() togetherWith (slideOutVertically { it / 12 } + fadeOut())
            },
            label = "screen",
        ) { s ->
            when (s) {
                Screen.HOME -> HomeScreen(
                    data = home, theme = theme, onTheme = vm::setTheme,
                    onCreate = { mode ->
                        pendingMode = mode; pendingTemplate = null
                        when (mode) {
                            ProjectMode.COMPARE -> pick2.launch(imageOnly)
                            ProjectMode.FAMILY -> pick8.launch(imageOnly)
                            else -> pick30.launch(imageOnly)
                        }
                    },
                    onOpen = vm::openSaved, onDelete = vm::deleteProject,
                    onTemplate = { t -> pendingTemplate = t; pendingMode = t.mode; pick30.launch(imageOnly) },
                    onDeleteTemplate = vm::deleteTemplate,
                )
                Screen.EDITOR -> EditorScreen(vm, onExport = { exporting = true })
            }
        }

        if (exporting && project != null) {
            ExportSheet(
                project = project!!, sizeFor = vm::sizeFor, onDismiss = { exporting = false },
                onSave = { req ->
                    if (Build.VERSION.SDK_INT < 29 && ctx.checkSelfPermission(Manifest.permission.WRITE_EXTERNAL_STORAGE) != PackageManager.PERMISSION_GRANTED) {
                        pendingExport = req to false
                        storagePermission.launch(Manifest.permission.WRITE_EXTERNAL_STORAGE)
                    } else vm.export(req, share = false)
                },
                onShare = { req -> vm.export(req, share = true) },
            )
        }

        gridUris?.let { uris ->
            var cols by remember { mutableStateOf(if (uris.size <= 4) 2 else 3) }
            AlertDialog(
                onDismissRequest = { gridUris = null },
                title = { Text("How many columns?") },
                text = {
                    Column {
                        val rows = (uris.size + cols - 1) / cols
                        Text("${uris.size} photos in $cols columns makes $rows ${if (rows == 1) "row" else "rows"}.")
                        Spacer(Modifier.height(8.dp))
                        ChipRow { (2..minOf(6, maxOf(2, uris.size))).forEach { c -> SelectChip("$c", cols == c) { cols = c } } }
                    }
                },
                confirmButton = { TextButton({ vm.startNew(ProjectMode.GRID, uris, cols); gridUris = null }) { Text("Make grid") } },
                dismissButton = { TextButton({ gridUris = null }) { Text("Cancel") } },
            )
        }

        busy?.let { b ->
            Box(Modifier.fillMaxSize().background(Color.Black.copy(alpha = 0.45f)), contentAlignment = Alignment.Center) {
                Column(
                    Modifier.padding(32.dp).background(MaterialTheme.colorScheme.surface, RoundedCornerShape(24.dp)).padding(24.dp),
                    horizontalAlignment = Alignment.CenterHorizontally,
                ) {
                    if (b.total > 0) LinearProgressIndicator(progress = { b.done.toFloat() / b.total }, Modifier.width(200.dp))
                    else CircularProgressIndicator()
                    Spacer(Modifier.height(16.dp))
                    Text(b.message, style = MaterialTheme.typography.titleMedium)
                    if (b.total > 0) Text("${b.done} of ${b.total}", style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
        }
        SnackbarHost(snackbar, Modifier.align(Alignment.BottomCenter).padding(bottom = 24.dp))
    }
}
