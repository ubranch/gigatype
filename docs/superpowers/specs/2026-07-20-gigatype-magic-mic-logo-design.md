# GigaType magic mic logo design

## goal

replace the current `G + waveform` identity with an original friendly, playful microphone mascot. keep GigaType's pink–purple palette, preserve clear recognition at Windows taskbar and tray sizes, and produce a clean transparent master through built-in image generation plus local chroma-key removal.

## visual direction

the mark is a smiling rounded microphone named `Magic Mic`. it has one compact capsule body, two dot eyes, one short curved smile, a simple stand, and one four-point sparkle at the upper-right. proportions favor a wide, centered square silhouette rather than a tall realistic microphone.

the mark contains no letter `G`, waveform, hand, wordmark, photorealism, 3D depth, texture, reflection, cast shadow, or fine decorative detail. the face remains readable at `16 px`; the sparkle may be omitted from monochrome tray variants when it cannot survive rasterization.

palette:

- pink: `#F59AC4`
- purple: `#B85BE8`
- dark plum outline: `#2D1F2A`
- warm white fill: `#FFF8FB`
- chroma-key source background only: `#00FF00`

## generation and transparency pipeline

use built-in `image_gen` in `logo-brand` mode to generate one centered square master on a perfectly flat `#00FF00` background. the background must have no gradient, texture, lighting variation, floor, shadow, or reflection; `#00FF00` must not appear in the subject. the mascot uses flat 2D shapes, generous padding, crisp outlines, and no text or watermark.

copy the selected generated source into `tmp/imagegen/`, then run the installed Python helper:

```powershell
python C:\Users\inspire\.codex\skills\.system\imagegen\scripts\remove_chroma_key.py `
  --input tmp/imagegen/gigatype-magic-mic-chroma.png `
  --out src-tauri/icons/gigatype-magic-mic.png `
  --auto-key border `
  --soft-matte `
  --transparent-threshold 12 `
  --opaque-threshold 220 `
  --despill
```

validate an alpha channel, fully transparent corners, plausible subject coverage, and no visible or statistically significant green fringe. retry once with `--edge-contract 1` if a thin fringe remains. if extraction damages the dark outline or image generation produces gradients/details that cannot be cleanly keyed, regenerate with stricter flat-shape constraints instead of masking defects manually.

the accepted transparent master is saved as `src-tauri/icons/gigatype-magic-mic.png`. chroma-key intermediates remain untracked and are removed after validation.

## integration

use the accepted imagegen master as the visual source of truth, then make a simplified deterministic SVG trace for crisp small-size rendering. update these identity surfaces together:

- `src-tauri/icons/gigatype.svg`: canonical app-icon composition, with the mascot on the existing pink–purple rounded-square background.
- `src/components/icons/GigaTypeMark.tsx`: matching accessible inline SVG mark; `GigaTypeLogo.tsx` keeps the `GigaType` wordmark.
- `src-tauri/icons/tray/gigatype.svg`: simplified transparent tray variant.
- `src-tauri/icons/logo.png`: replace the remaining upstream hand raster.
- generated desktop/mobile icon rasters under `src-tauri/icons/` and colored tray raster `src-tauri/resources/gigatype.png` through their existing source-of-truth generation path.

do not modify product name, bundle identifier, application copy, model behavior, accelerator behavior, or release version.

## validation

visual checks cover transparent master edges and the mark at `16`, `24`, `32`, `64`, and `256 px`, on light and dark backgrounds. the face, capsule, stand, and silhouette must remain recognizable; no green fringe or accidental upstream Handy hand may remain.

repository checks:

```powershell
bun test tests/gigatype-branding.test.ts tests/dropdown-accessibility.test.tsx
bun run build
bun run lint
bun run format:check
git diff --check
```

inspect regenerated PNG, ICO, and ICNS outputs after generation. production Windows installer rebuild and GitHub release replacement are outside this logo-only change unless separately requested.

## acceptance

work is complete when the approved Magic Mic design exists as a validated transparent imagegen master, every shipped GigaType identity surface uses its matching simplified geometry, small-size checks remain legible, repository branding/accessibility/build gates pass, and unrelated Handy provenance or internal compatibility identifiers remain untouched.
