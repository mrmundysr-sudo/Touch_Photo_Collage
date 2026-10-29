# Touch Gesture Standard (Mundy Morning Studios) — v1.1

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
12. **Direct manipulation (v1.1).** The content must follow the finger on every input event, from the first pixel, with
    no smoothing animation, easing toward a target, snapping, rounding or throttling. Zoom factors and offsets stay in
    full floating-point precision (accumulate in `Float`/`Double`, never round to pixels or zoom steps). Limits clamp
    incrementally, so reversing direction at a limit responds immediately (no "dead travel").
13. **Live layer, commit once.** While a finger is down, apply movement to *uncommitted live state* and draw it directly
    (GPU). Do not copy/modify the document, re-render, decode images, run detection, save or recompose the screen per
    event. Prefetch the bitmap when the item is selected. On release, commit the final value once (a single undo step).
    Draw live and final output with the same code so there is no visual pop on commit.
14. **Touch slop without a jump.** Never swallow the first pixels and then apply them at once. Apply movement from the
    first pixel through a soft start (`GestureKnee`): inside the first 4 dp the movement is scaled by `|v|/4dp`, which is
    0 at the touch point and 1 at 4 dp, so it is continuous (no step) and filters resting tremor. A touch that lifts
    inside 3/4 of the platform slop is a **tap**: the live movement is discarded and nothing is committed (so a tap to
    select never disturbs an automatic placement).
15. **Long press means stillness.** A long press fires only if the finger barely moved (< 2 dp) during the last 250 ms of
    the long-press time. A slow, careful drag keeps moving and therefore stays a drag, however small its travel.
16. **Adjustable sensitivity.** `zoomSensitivity` 0.25x to 3x (default 1.0x = 160 dp per doubling), with Fine (0.4x),
    Normal and Fast presets, on a logarithmic slider; persisted.
17. **Measurable.** Offer an opt-in frame-timing readout (`FrameTimingOverlay`: fps, average, worst frame, janky frames).
    Target: display-synchronised updates (60 fps, or the panel's rate) with no frame over ~20 ms while dragging.

## Reference implementation: `touch-gesture-standard` module
| API | Purpose |
|---|---|
| `TouchMode { PAN, ZOOM }` | the two modes |
| `OneFingerMath.zoomFactor / travelFor / clampZoom` | pure, unit-tested maths |
| `GestureSettings(prefs)` | persisted `mode`, `pinchEnabled`, `introSeen` |
| `OneFingerMath.pxPerDoubling / sensitivityFromSlider / sliderFromSensitivity` | sensitivity maths |
| `GestureKnee` | continuous soft start (no slop jump) |
| `touchGesture(down, mode, pinchEnabled, pxPerDoubling, deadzonePx, stillnessPx, onBegin, onPan, onZoom)` | the shared gesture loop; returns `TAP`, `LONG_PRESS` or `MOVED` |
| `GestureModeBar(...)`, `GestureIntroDialog(...)` | the standard UI (mode bar, first-use text, sensitivity, pinch, frame timing) |
| `FrameStats`, `FrameTimingOverlay` | frame-pacing measurement |

### Integration sketch
```kotlin
val live = LiveState()                         // your uncommitted crop/offset; Compose state read ONLY in draw
Modifier.pointerInput(Unit) {
  awaitEachGesture {
    val down = awaitFirstDown()
    when (touchGesture(down, mode, pinch, OneFingerMath.pxPerDoubling(1.dp.toPx(), sensitivity),
                       deadzonePx = 4.dp.toPx(), stillnessPx = 2.dp.toPx(),
                       onBegin = { live.begin(currentItem) },       // snapshot start state, get a cached bitmap
                       onPan = { d -> live.pan(d) },
                       onZoom = { f, c -> live.zoomBy(f, c ?: itemCentre) })) {
      GestureOutcome.MOVED -> commit(live)                         // one undo step
      GestureOutcome.TAP -> live.clear()                           // discard
      GestureOutcome.LONG_PRESS -> { live.clear(); /* app-specific, e.g. pick the item up */ }
    }
  }
}
// draw: Canvas { if (live.active) drawItemWith(live.zoom, live.cx, live.cy) }   // GPU, no recomposition
```
Place `GestureModeBar` directly under the content (pass `zoomLabel` as a lambda so per-frame zoom changes recompose only the readout), show `GestureIntroDialog` when `!settings.introSeen`, and expose
`GestureSettings` through your ViewModel. Add the module via `include(":touch-gesture-standard")` (or the Touch-Modules registry once published).

## Testing checklist
Slide up/down zooms in/out; small drags make small changes; PAN moves and never changes zoom; ZOOM never moves the
centre; RESET restores the start and is undoable; pinch works when on and is ignored when off; mode survives a restart;
targets >= 48 dp; no distortion (visible window keeps the target's aspect). See `GestureUiTest` for real-touch examples.

## What caused choppiness in v1 (lessons)
- Every touch event rebuilt the document and triggered a full software re-render of the whole collage on a worker thread
  (renders queued, results dropped), a full-screen recomposition and an autosave: the visible rate was the renderer's rate.
- Zooming changes the needed image resolution, so crossing a power of two re-decoded the photo mid-gesture.
- The touch-slop circle swallowed the first 8 to 16 dp of movement and then applied it as one jump.
- The long-press timer was only cancelled by leaving the slop circle, so slow drags became long presses.
v1.1 fixes all four (live GPU layer + one commit, prefetched fixed-size bitmap, `GestureKnee`, stillness-based long press).

## Testing checklist (v1.1 additions)
Every event changes the live value by about one finger-pixel; per-event change never exceeds the soft-start bound; no
repeated (quantised) values; the project and the rendered frame are untouched during the gesture; the committed value
equals the live value bit for bit; reversing at a limit responds immediately; a slow drag is not a long press; tap and
tremor commit nothing; sensitivity scales travel per doubling. See `GestureUiTest` and `SmoothnessTest`.
Hardware: switch on **Show frame timing** (? button) and drag; expect ~60 fps and a worst frame under ~20 ms.
