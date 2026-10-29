# Release builds

`./gradlew :app:assembleRelease :app:bundleRelease` produces the R8-minified, resource-shrunk **unsigned** APK
(`app/build/outputs/apk/release/app-release-unsigned.apk`) and Android App Bundle
(`app/build/outputs/bundle/release/app-release.aab`).

## Signing (owner only)
The repository contains **no signing material**. For Play, sign the bundle with the owner's upload key, outside Git:
```bash
jarsigner -keystore "$UPLOAD_KEYSTORE" app-release.aab "$UPLOAD_ALIAS"        # bundle for Play
apksigner sign --ks "$UPLOAD_KEYSTORE" --out app-release-signed.apk app-release-unsigned.apk   # APK for sideloading
```
Never commit keystores or passwords. Use Play App Signing.

## Versioning
Bump `versionCode` (integer, must increase) and `versionName` in `app/build.gradle.kts` for each release.

## Shrinking notes
- Enum lookups in project JSON are static (no reflection); `consumer-rules.pro` in both library modules keeps enum `values()`/`valueOf()`.
- ML Kit and Compose ship their own consumer rules.
- Debug and CI builds are not minified. Smoke-test a release build on a device before publishing (open an old project, drag/zoom, export).

## Permissions
ML Kit merges `INTERNET` into the manifest (optional model download and telemetry). This app uses the bundled model only and
promises offline operation, so `tools:node="remove"` strips it; `AppSmokeTest.appRequestsNoInternetPermission...` fails the
build if it returns. Any app that embeds `collage-engine` should do the same (see docs/INTEGRATION.md).

## Checklist before Play
Signed bundle; target API current; data-safety form (no data collected, no INTERNET permission); store listing assets (not in repo).
