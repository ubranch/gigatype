# GigaType Magic Mic Logo Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** replace the current `G + waveform` visuals with the approved friendly Magic Mic mascot, including a transparent imagegen master and every shipped icon surface.

**Architecture:** built-in `image_gen` creates one flat chroma-key raster source; the installed Python helper produces the transparent master. a simplified deterministic SVG trace supplies crisp React, tray, and Tauri icon geometry, while generated raster mirrors remain derived artifacts.

**Tech Stack:** built-in `image_gen`, Python chroma-key helper, SVG, React/TypeScript, ImageMagick, Bun, Tauri 2 icon generator.

## Global Constraints

- keep `#F59AC4`, `#B85BE8`, `#2D1F2A`, and `#FFF8FB`.
- use `#00FF00` only as the removable flat source background.
- include no `G`, waveform, hand, wordmark, photorealism, 3D depth, texture, reflection, cast shadow, or fine detail.
- preserve `GigaType`, `io.github.ubranch.gigatype`, `0.9.3-gigatype.2`, model behavior, and accelerator behavior.
- do not rebuild installers or replace GitHub release assets.

## File Structure

- Create: `src-tauri/icons/gigatype-magic-mic.png` — validated transparent imagegen master.
- Modify: `src-tauri/icons/gigatype.svg` — canonical rounded-square app icon.
- Modify: `src/components/icons/GigaTypeMark.tsx` — accessible React mark.
- Modify: `src-tauri/icons/tray/gigatype.svg` — colored tray mark.
- Modify: `src-tauri/icons/tray/tray_idle.svg` — white monochrome tray mark.
- Modify: `src-tauri/icons/tray/tray_idle_dark.svg` — dark monochrome tray mark.
- Modify: `src-tauri/icons/logo.png` — remove remaining upstream hand raster.
- Modify: `src-tauri/icons/**` — Tauri-generated desktop/mobile raster mirrors.
- Modify: `src-tauri/resources/gigatype.png`, `tray_idle.png`, `tray_idle_dark.png` — regenerated 64 px tray mirrors.
- Modify: `tests/gigatype-branding.test.ts` — Magic Mic source/master contract.

---

### Task 1: Generate and validate transparent master

**Files:**

- Create: `tmp/imagegen/gigatype-magic-mic-chroma.png`
- Create: `src-tauri/icons/gigatype-magic-mic.png`

**Interfaces:**

- Consumes: approved Magic Mic geometry and exact palette.
- Produces: RGBA PNG visual reference used by Task 2.

- [ ] **Step 1: Generate flat source with built-in imagegen**

Use this exact prompt:

```text
Use case: logo-brand
Asset type: square desktop app mascot master
Primary request: create an original friendly playful smiling microphone mascot for GigaType, replacing the prior G and waveform concept entirely
Scene/backdrop: perfectly flat solid #00FF00 chroma-key background
Subject: one centered rounded microphone capsule, two dot eyes, one short curved smile, simple stand, one four-point sparkle at upper-right
Style/medium: polished flat 2D vector-friendly logo, bold clean geometry
Composition/framing: square, centered, balanced wide silhouette, generous even padding, readable at 16 px
Color palette: warm white #FFF8FB, dark plum #2D1F2A, pink #F59AC4, purple #B85BE8; never use #00FF00 in subject
Constraints: uniform background; crisp separated edges; no text; no letter G; no waveform; no hand; no shadow; no gradient or texture in background; no floor, reflection, watermark, 3D, photorealism, or tiny detail
```

Expected: one square source with a uniform green border/background and isolated opaque mascot.

- [ ] **Step 2: Copy tool output into workspace**

Copy the tool-returned generated PNG to `tmp/imagegen/gigatype-magic-mic-chroma.png` without modifying pixels.

- [ ] **Step 3: Remove chroma with Python**

```powershell
uv run --with pillow python C:\Users\inspire\.codex\skills\.system\imagegen\scripts\remove_chroma_key.py `
  --input tmp/imagegen/gigatype-magic-mic-chroma.png `
  --out src-tauri/icons/gigatype-magic-mic.png `
  --auto-key border `
  --soft-matte `
  --transparent-threshold 12 `
  --opaque-threshold 220 `
  --despill
```

Expected: exit `0`; output PNG has RGBA alpha and transparent corners.

- [ ] **Step 4: Validate transparent pixels and fringe**

Inspect `src-tauri/icons/gigatype-magic-mic.png` on light/dark checkerboards. use `--edge-contract 1` once only if green fringe remains; regenerate instead if subject edges are damaged.

---

### Task 2: Lock Magic Mic contract before integration

**Files:**

- Modify: `tests/gigatype-branding.test.ts`

**Interfaces:**

- Consumes: transparent master from Task 1.
- Produces: failing contract requiring the Magic Mic sources and RGBA master.

- [ ] **Step 1: Extend PNG header helper**

Add `colorType: bytes[25]` to `readPngHeader` so `6` proves RGBA.

- [ ] **Step 2: Replace old geometry assertions**

Require `data-brand="magic-mic"`, `data-part="mic-body"`, and `data-part="face"` in all three tray sources; reject the old paths `M84 43a32 32 0 1 0 4 42V66H65` and `M43 57v14M53 51v26M63 57v14`.

Add:

```typescript
const master = readPngHeader("src-tauri/icons/gigatype-magic-mic.png");
expect(master.signature).toBe("89504e470d0a1a0a");
expect(master.width).toBe(master.height);
expect(master.colorType).toBe(6);
expect(read("src-tauri/icons/gigatype.svg")).toContain(
  'data-brand="magic-mic"',
);
expect(read("src/components/icons/GigaTypeMark.tsx")).toContain(
  'data-brand="magic-mic"',
);
```

- [ ] **Step 3: Run red test**

```powershell
bun test tests/gigatype-branding.test.ts
```

Expected: FAIL because old SVG/React geometry lacks Magic Mic markers.

---

### Task 3: Integrate SVG geometry and regenerate mirrors

**Files:**

- Modify: `src-tauri/icons/gigatype.svg`
- Modify: `src/components/icons/GigaTypeMark.tsx`
- Modify: `src-tauri/icons/tray/gigatype.svg`
- Modify: `src-tauri/icons/tray/tray_idle.svg`
- Modify: `src-tauri/icons/tray/tray_idle_dark.svg`
- Modify: `src-tauri/icons/logo.png`
- Modify: generated icon/tray rasters

**Interfaces:**

- Consumes: Task 1 reference and Task 2 contract.
- Produces: consistent Magic Mic identity at every runtime/package surface.

- [ ] **Step 1: Trace simplified app/UI geometry**

Use one rounded capsule body, two circular eyes, one cubic smile, one U-shaped support/stand, and one four-point sparkle. add `data-brand="magic-mic"`, `data-part="mic-body"`, and `data-part="face"` markers. preserve existing accessible role/label behavior in `GigaTypeMark.tsx`.

- [ ] **Step 2: Trace simplified tray geometry**

Use the same body/face/stand silhouette in `viewBox="0 0 128 128"`; omit background rectangles and sparkle. colored source keeps `#F59AC4`/`#B85BE8`; monochrome sources keep `#FFFFFF` or `#2D1F2A`.

- [ ] **Step 3: Regenerate app icon mirrors**

```powershell
bun run tauri icon src-tauri/icons/gigatype.svg --output src-tauri/icons
Copy-Item src-tauri/icons/ios/AppIcon-512@2x.png src-tauri/icons/logo.png -Force
```

Expected: PNG, ICO, ICNS, iOS, and Android icons regenerate; `logo.png` shows Magic Mic.

- [ ] **Step 4: Regenerate tray rasters**

```powershell
bun run tauri icon src-tauri/icons/tray/gigatype.svg --output tmp/imagegen/gigatype-tray-render
bun run tauri icon src-tauri/icons/tray/tray_idle.svg --output tmp/imagegen/tray-idle-render
bun run tauri icon src-tauri/icons/tray/tray_idle_dark.svg --output tmp/imagegen/tray-idle-dark-render
Copy-Item tmp/imagegen/gigatype-tray-render/64x64.png src-tauri/resources/gigatype.png -Force
Copy-Item tmp/imagegen/tray-idle-render/64x64.png src-tauri/resources/tray_idle.png -Force
Copy-Item tmp/imagegen/tray-idle-dark-render/64x64.png src-tauri/resources/tray_idle_dark.png -Force
```

Expected: three transparent `64x64` PNG files.

- [ ] **Step 5: Run focused green tests**

```powershell
bun test tests/gigatype-branding.test.ts tests/dropdown-accessibility.test.tsx
```

Expected: all tests pass.

---

### Task 4: Final visual and repository gates

**Files:**

- Verify only task-owned files.

**Interfaces:**

- Consumes: integrated source and generated mirrors.
- Produces: completion evidence.

- [ ] **Step 1: Inspect visual outputs**

Inspect transparent master, `src-tauri/icons/icon.png`, `32x32.png`, `src-tauri/icons/logo.png`, and all three tray PNGs on light and dark backgrounds.

- [ ] **Step 2: Run source gates**

```powershell
bun run build
bun run lint
bun run format:check
git diff --check
```

Expected: every command exits `0`.

- [ ] **Step 3: Review scope**

Confirm no installer, model, accelerator, version, bundle identifier, or unrelated user file changed. leave packaging/release work unrun.
