# iOS port notes

The iOS app lives in `ios/` and is a native SwiftUI/UIKit port of the Android app. Android remains the source of truth
for behaviour and look; this page records what carried over 1:1 and where the platform forced a difference.

## Feature parity
| Area | Android | iOS |
|---|---|---|
| Create | Collage, Side by side, Family resemblance, Photo grid (column picker), saved templates | same, same defaults per mode |
| Photo selection | system photo picker (30 / 2 / 8 / 20 photos) | `PhotosPicker` (out of process, **no permission needed**), same limits |
| Layouts | generated tilings for any N, auto layout + ratio by crop cost, "Artistic" mosaics | same code path; mosaics use an exact `java.util.Random` port so a seed gives the same layout |
| Canvas shapes | 8 presets + custom ratio | same |
| Editing | rotate, mirror, fit/fill, reset, replace, move earlier/later, remove, swap by long-press drop | same |
| Style | spacing, margin, corners, border + colour, backgrounds (colour, gradient, 6 textures, transparent) | same, textures generated procedurally with the same seed |
| Adjust | 8 filters, brightness, contrast, saturation, warmth, sharpness, apply to one/all | same matrices (`ColorMath`), applied with Core Image |
| Text | overlays: fonts, size, colour, bold/italic/shadow/label box, align, tilt, drag to move | same (iOS system fonts, see below) |
| Faces | smart crop, align faces, never-crop, captions | same maths; detector is Apple Vision instead of ML Kit |
| Undo/redo | 60 steps, one step per gesture/slider drag | same |
| Export | JPEG/PNG, Standard 2048 / Maximum 4800, transparent PNG, rendered once from originals | same; memory budget from `os_proc_available_memory()` |
| Save | gallery (MediaStore) | Photos library, **add-only** permission, asked at first save |
| Share | Android share sheet | `UIActivityViewController` |
| Persistence | private files, atomic writes, autosave 0.7 s | same layout in Application Support, plus immediate save when the app leaves the foreground |
| Theme | system / light / dark | same palette (dynamic colours) |
| Accessibility | TalkBack actions on canvas, 56 dp gesture targets | VoiceOver custom actions + adjustable (swipe up/down zooms), 56 pt targets, Dynamic-Type-safe layouts |

## Touch Gesture Standard (one finger first)
Ported from `touch-gesture-standard` as `OneFingerGestureEngine`, a pure state machine driven by raw `UITouch` events from
`CanvasUIView`. There is no system gesture recogniser in the path, so nothing can delay, steal or smooth the first points.
- **PAN**: one finger drags the photo. **ZOOM**: one finger slides up to zoom in / down to zoom out, exponential, 160 pt per
  doubling, adjustable sensitivity 0.25x–3x. **RESET** restores the automatic placement. Pinch is optional and can be switched off;
  one-finger zoom never depends on it.
- Soft start (`GestureKnee`, 4 pt), tap tolerance of 3/4 touch slop (a tap only selects and commits nothing), long press only when the
  finger is still (slow drags stay drags), live drawing on a dedicated layer with a single commit (one undo step) on release.
- Selecting, dragging text, long-press-to-swap and photo gestures share one touch pipeline: the first touch decides the target
  (text box, else cell) and the rest of the gesture belongs to it.

## Platform differences
- **Face detection**: Vision `VNDetectFaceRectanglesRequest` replaces ML Kit. Boxes are padded the same way, so crops are very
  similar but not pixel-identical. On failure the crop falls back to the centre, as on Android.
- **Fonts**: Android's generic families map to iOS system fonts (Clean/Medium = SF, Narrow = Avenir Next Condensed, Serif = New
  York, Typewriter = Menlo, Script = Snell Roundhand, Casual = Marker Felt). Exported text therefore looks slightly different
  between platforms.
- **Colour management**: images are drawn in sRGB; Display-P3 originals are converted, so very saturated colours may differ slightly.
- **Gallery album**: Android saves into `Pictures/Touch Photo Collage`. iOS saves to the library without creating an album
  (that would need full library access, which the app deliberately never requests).
- **Back navigation**: the on-screen back button; there is no Android system-back equivalent.
- **Landscape**: the editor switches to a side-by-side layout (canvas left, controls right).
- **Backups**: data is in Application Support and is included in iCloud/device backups (Android disables backup).
- **iPad / Mac**: iPhone only (`TARGETED_DEVICE_FAMILY = 1`, Mac "Designed for iPhone" off).

## Verification
Everything is verified by the simulator CI (`.github/workflows/ios-ci.yml`): unit tests (engine, renderer, export, gesture engine,
app model), UI tests that drive the real app with real touches, a no-signing device build, and a small-screen (iPhone SE)
re-run of the main flows. Screenshots are committed to `ios/docs/screenshots/` by CI.

## Not covered / limitations
- No physical-device testing yet: frame pacing and the system photo picker are only exercised on the simulator (the picker is
  replaced by synthetic sample photos in UI tests because it runs out of process).
- Vision face detection is only exercised for the "no faces found" path (synthetic photos); detection quality on real portraits
  needs a device check.
- Apple signing, provisioning, App Store Connect and TestFlight are intentionally not part of this branch.
