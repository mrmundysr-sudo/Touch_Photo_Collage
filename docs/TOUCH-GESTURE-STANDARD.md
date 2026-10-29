# Touch Gesture Standard (Mundy Morning Studios) — v1

Applies to every Touch app that lets the user **zoom or pan content** (photos, canvases, maps, boards): Touch Photo
Collage, Touch Cartoon Studio, Touch Memories and future image editors. Pinch and two-finger drags are hard for people
with larger fingers or limited dexterity, so every such surface must also offer one-finger control.

## Requirements
1. **Mode buttons.** Two large, always-visible buttons: **PAN** and **ZOOM** (radio behaviour, one active).
2. **PAN:** one finger dragging in any direction moves the content.
3. **ZOOM:** one finger sliding **up zooms in, down zooms out**. Exponential and proportional
   (`factor = 2^(-dy / pxPerDoubling)`, default 160 dp per doubling): small movements give small changes, equal
   movements give equal ratios, and up-then-down returns exactly to the start. Horizontal movement is ignored in ZOOM.
4. **RESET** restores the automatic/starting view (in Touch Photo Collage: the automatic face alignment or starting crop).
   Reset is undoable.
5. **No distortion.** Zoom and pan only change a uniform-scale window; the aspect ratio is never altered.
6. **Visible state.** A banner states in words what one finger does now ("PAN: drag one finger to move the photo",
   "ZOOM: slide one finger up to zoom in, down to zoom out") plus the current zoom; the banner is a polite live region.
7. **Pinch stays optional.** Two-finger pinch/pan keeps working and can be switched off by the user.
8. **Remembered.** Mode, pinch preference and "intro seen" persist between sessions.
9. **Accessibility.** Targets at least 56 dp tall; content descriptions and selected state on every control; TalkBack
   custom actions for zoom in/out, move left/right/up/down and reset on the canvas.
10. **First-use explanation.** A short dialog on first use, reopenable from a `?` button, with the pinch switch.
11. **Games.** Do **not** apply the standard to gestures that already have gameplay meaning. Use it only on
    editing/viewing surfaces; if a game has a zoomable board, offer the mode bar there and leave play gestures unchanged.
12. **Slop and long-press.** Drags start immediately after touch slop; a still press (system long-press time) is reserved
    for app-specific actions (here: pick up a photo to swap it). Long-press must never delay a drag.

## Reference implementation: `touch-gesture-standard` module
| API | Purpose |
|---|---|
| `TouchMode { PAN, ZOOM }` | the two modes |
| `OneFingerMath.zoomFactor / travelFor / clampZoom` | pure, unit-tested maths |
| `GestureSettings(prefs)` | persisted `mode`, `pinchEnabled`, `introSeen` |
| `classifyTouchStart(down)` | tap / long-press / move / multi-touch, with slop-crossing travel |
| `oneFingerOrPinchGesture(mode, pinchEnabled, pxPerDoubling, onPan, onZoom, initialDelta)` | the shared gesture loop |
| `GestureModeBar(...)`, `GestureIntroDialog(...)` | the standard UI |

### Integration sketch
```kotlin
Modifier.pointerInput(Unit) {
  awaitEachGesture {
    val down = awaitFirstDown()
    var start = Offset.Zero
    when (classifyTouchStart(down) { start = it }) {
      TouchStart.TAP -> return@awaitEachGesture
      TouchStart.LONG_PRESS -> { /* app-specific, e.g. pick up item */ return@awaitEachGesture }
      else -> oneFingerOrPinchGesture(mode, pinch, 160.dp.toPx(),
                onPan = { d -> pan(d) }, onZoom = { f, c -> zoom(f, c ?: contentCentre) }, initialDelta = start)
    }
  }
}
```
Place `GestureModeBar` directly under the content, show `GestureIntroDialog` when `!settings.introSeen`, and expose
`GestureSettings` through your ViewModel. Add the module via `include(":touch-gesture-standard")` (or the Touch-Modules registry once published).

## Testing checklist
Slide up/down zooms in/out; small drags make small changes; PAN moves and never changes zoom; ZOOM never moves the
centre; RESET restores the start and is undoable; pinch works when on and is ignored when off; mode survives a restart;
targets >= 48 dp; no distortion (visible window keeps the target's aspect). See `GestureUiTest` for real-touch examples.
