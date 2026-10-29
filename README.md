# Touch Photo Collage

Offline, private photo collage maker for Android (Kotlin, Jetpack Compose). Mundy Morning Studios.

- **One-touch flow:** pick photos -> automatic layout and canvas shape -> live preview -> save or share.
- **Layouts:** 1 to 30 photos; rows, columns, grids, feature layouts, pinwheel and artistic mosaics; side-by-side / stacked comparisons; any canvas ratio.
- **Style:** spacing, margin, rounded corners, photo borders; colour, gradient, textured or transparent backgrounds.
- **Smart positioning:** on-device face detection keeps faces in frame; *Family Resemblance* aligns faces to the same size and height; never distorts; pinch/drag overrides; rotate, mirror; "never crop" mode.
- **Editor:** brightness, contrast, saturation, warmth, sharpness, filters, text overlays, captions, undo/redo, projects autosave and reopen. Non-destructive.
- **Export:** JPEG/PNG, standard or maximum resolution, save to gallery or share sheet, transparent PNG.
- **Privacy:** no internet permission, no accounts, no cloud. Photos are chosen with the system photo picker.

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) and [docs/INTEGRATION.md](docs/INTEGRATION.md).

## Build
```bash
export ANDROID_HOME=/path/to/sdk
./gradlew testDebugUnitTest assembleDebug
```
APK: `app/build/outputs/apk/debug/app-debug.apk`. CI: `.github/workflows/autobuild.yml` (shared Touch AutoBuild).
