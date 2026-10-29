# Claude instructions (Touch Photo Collage)

Branching, the build/repair loop and approvals follow the shared Touch AutoBuild process:
https://github.com/mrmundysr-sudo/touch-development/blob/main/AUTOBUILD.md

Short version: work only on a `claude/<slug>` branch, push to trigger AutoBuild, read failures, repair up to 3 times,
then report. Never merge to `main`, publish releases, touch signing material or secrets, or delete anything without
the owner's explicit approval. APK delivery standard: autobuild/APK-DELIVERY.md in the hub; settings in `.autobuild/deliver.conf`.

## Layout
- `collage-engine/` reusable Android library (no UI): layout, crop math, face-aware cropping, rendering, export, project storage.
- `app/` Compose UI (home, editor, export sheet) + `CollageViewModel`.
- `docs/` architecture and integration guide.

## Rules
- Engine stays UI-free. Pure math (layout, crop, orientation, colour) must stay Android-free and unit-tested.
- Originals are never modified: photos are copied into app-private storage and edited non-destructively.
- No network, no INTERNET permission, no paid/cloud APIs. Face detection is ML Kit's *bundled* on-device model.
- Run `./gradlew testDebugUnitTest assembleDebug` before pushing (needs ANDROID_HOME).
