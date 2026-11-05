# Touch Photo Collage for iOS

Native SwiftUI/UIKit port of the Android app (`app/`, `collage-engine/`, `touch-gesture-standard/`). The Android app is the
source of truth for behaviour and visual identity; nothing outside `ios/` (plus `.github/workflows/ios-ci.yml`) was changed.

| | |
|---|---|
| App name | Touch Photo Collage |
| Bundle ID | `com.mundymorning.touchphotocollage` (same identifier as the Android `applicationId`) |
| Deployment target | iOS 16.0, iPhone (portrait and landscape) |
| Xcode project | `ios/TouchPhotoCollage.xcodeproj` (Xcode 16+, folder-synchronised groups), scheme `TouchPhotoCollage` |
| Dependencies | none (Apple frameworks only: SwiftUI, UIKit, Core Graphics, Core Image, ImageIO, Vision, PhotosUI, Photos) |

## Layout
- `TouchPhotoCollage/Engine` pure Swift, no UIKit: `Layout`, `CropMath`, `Orientation`, `FaceCrop`, `ColorMath`, `Models`,
  `ProjectJson` (same JSON keys as Android), `ProjectOps`, `Stores`.
- `TouchPhotoCollage/Platform` ImageIO decoding, Core Graphics `CollageRenderer` (one path for preview, live drag and export),
  backgrounds, text, Core Image colour filters, `Exporter`, `PhotoSaver`, Vision `FaceFinder`, `ImageImporter`.
- `TouchPhotoCollage/Gesture` Touch Gesture Standard: `OneFingerGestureEngine` (pure state machine), settings, math, frame meter.
- `TouchPhotoCollage/UI` SwiftUI screens and the UIKit `CollageCanvasView`; `App/AppModel.swift` is the port of `CollageViewModel`.
- `TouchPhotoCollageTests` unit tests (engine, renderer/export, gesture engine, app model); `TouchPhotoCollageUITests` simulator UI tests.
- `docs/` port notes and screenshots.

## Build and test
```bash
xcodebuild test -project ios/TouchPhotoCollage.xcodeproj -scheme TouchPhotoCollage \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' CODE_SIGNING_ALLOWED=NO
```
CI (`.github/workflows/ios-ci.yml`) does this on a macOS runner for every push to `claude/ios-**`, also compiles for a
device without signing, and commits fresh screenshots to `ios/docs/screenshots/`. It uses no secrets and no Apple credentials.

UI tests launch the app with `-UITestSeed` (synthetic sample photos instead of the out-of-process photo picker),
`-UITestReset`, `-UITestIntroSeen`, `-UITestTheme dark|light`, `-UITestPhotosDenied`. These switches are inert in normal use.
