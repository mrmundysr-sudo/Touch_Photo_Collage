# Using collage-engine from another Touch app

The engine is a separate Gradle module with no UI dependency. Until it is published to Touch-Modules, include it as a module (copy or git submodule) and `implementation(project(":collage-engine"))`.

```kotlin
val store = ProjectStore(File(filesDir, "collage"))
val photos = uris.map { ImageImporter(context, store.mediaDir).import(it) }      // importing
var project = ProjectOps.create(photos, ProjectMode.COMPARE, System.currentTimeMillis()) // layout + auto crop
project = ProjectOps.withLayout(project, LayoutGenerator.candidates(photos.size)[2])     // layout generation
val bmp = CollageRenderer(FileBitmapProvider(store.mediaDir)).render(project, 1080, 1080) // rendering
Exporter(context, store.mediaDir).saveToGallery(project, ExportRequest(ExportFormat.PNG, ExportQuality.MAXIMUM)) // export
store.save(project)                                                                       // serialization
```
Face-aware cropping: run `MlKitFaceFinder().find(ref, store.mediaDir)` off the main thread, then `ProjectOps.withFaces(project, ref.id, faces)`. Implement `FaceFinder` to use another detector.
Share via `Exporter.prepareShare(project, req, "<applicationId>.fileprovider")` (declare a FileProvider with a `cache-path` `shared/`).
Requirements: minSdk 26, ML Kit `face-detection` is pulled in transitively. ML Kit merges the `INTERNET` permission into your manifest; if your app must work offline, remove it with `<uses-permission android:name="android.permission.INTERNET" tools:node="remove" />` (bundled-model detection needs no network).
