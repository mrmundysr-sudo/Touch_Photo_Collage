# Architecture

```
app (Compose UI) ──▶ collage-engine (library, no UI)
```

## collage-engine packages
| Package | Role | Android-free? |
|---|---|---|
| `model` | `FRect` geometry | yes |
| `transform` | `Affine`, `Orientation` (EXIF 1-8 + rotation + mirror), `CropMath` (cover/fit regions, pan, zoom-about-point, decode sample size) | yes |
| `layout` | `LayoutTemplate`, `LayoutGenerator` (any N), `LayoutEngine` (margin/spacing to pixels), auto layout+ratio by crop cost | yes |
| `face` | `FaceCrop` (smart crop, cross-photo face alignment), `FaceFinder`/`MlKitFaceFinder` | maths yes; detector no |
| `color` | `ColorMath` colour matrices, `Sharpen` | yes |
| `project` | models, `ProjectJson` (versioned), `ProjectStore`/`TemplateStore` (atomic file storage), `ProjectOps` | mostly (JSON/IO use org.json) |
| `io` | `ImageImporter` (private copy), `BitmapLoader`, `BitmapProvider` | no |
| `render` | `CollageRenderer`, backgrounds, text; one path for preview and export | no |
| `export` | `ExportSizing`, `Exporter` (MediaStore, share cache) | no |

## Key decisions
- **Display space.** Every crop, face box and gesture is in the coordinate space of the photo *after* EXIF orientation, user rotation and mirroring. The renderer composes one affine matrix from raw pixels, so orientation can't drift between preview and export.
- **Never distort.** The visible region always has the cell's pixel aspect; scaling is uniform.
- **Non-destructive.** Photos are copied once into `files/collage/media`; edits are parameters in the project JSON.
- **Memory.** Bitmaps are decoded at the smallest power-of-two sample that still meets the needed resolution; OOM retries coarser; export size is clamped by a heap budget; preview uses an LRU cache.
- **Faces.** ML Kit bundled model, on device, bounding boxes only (no identity). Missing/failed detection falls back to centre crop.
