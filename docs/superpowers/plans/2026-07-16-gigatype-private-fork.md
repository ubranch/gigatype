# GigaType Private Fork Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship the approved working tree as a private, friend-ready GigaType fork with GigaAM Multilingual 220M/600M CPU and CUDA support, complete Windows documentation, and four verified private release installers.

**Architecture:** Preserve Handy's upstream Git history and internal implementation names where they are not user-facing, but replace every shipped identity surface with GigaType. Keep model catalog, bundle download, inference, and accelerator boundaries unchanged; isolate the fork from upstream signing and update infrastructure. Publish source to private `ubranch/GigaType`, then attach rebuilt CPU and CUDA NSIS/MSI packages to a private release.

**Tech Stack:** Tauri 2.11, Rust 2021, React 18, TypeScript 5.6, Bun, ONNX Runtime 1.24.2, CUDA 13.0.2, cuDNN 9.16.0.29, PowerShell 7, GitHub CLI.

## Global Constraints

- Include every approved current working-tree change; exclude no GigaAM, CUDA, accessibility, model-source, or Clippy fix.
- Product name is `GigaType`; repository is private `ubranch/GigaType`.
- Release version is `0.9.3-gigatype.1`; release tag is `v0.9.3-gigatype.1`.
- Bundle identifier is `io.github.ubranch.gigatype`.
- Existing `origin` stays `https://github.com/cjpais/Handy.git`; add `private` for `https://github.com/ubranch/GigaType.git`.
- Public surfaces use GigaType; internal `HandyKeys`, historical attribution, dependency URLs, and upstream references may retain their exact names.
- Remove upstream signing and automatic updater integration; releases remain unsigned and private.
- Release only Windows x64 CPU and NVIDIA CUDA 13 packages; macOS/Linux source support remains without release proof.
- Do not bundle model weights. GigaAM models continue downloading from pinned Hugging Face revisions.
- Publish exactly four installers named `GigaType_0.9.3-gigatype.1_x64-setup.exe`, `GigaType_0.9.3-gigatype.1_x64_en-US.msi`, `GigaType_0.9.3-gigatype.1_x64-cuda13-setup.exe`, and `GigaType_0.9.3-gigatype.1_x64-cuda13_en-US.msi`.
- Grant the friend repository permission `pull` only after receiving their exact GitHub username.
- Never commit `dist/`, downloaded models, CUDA archives, build caches, credentials, or installers.

## File Structure

- Product identity: `package.json`, `bun.lock`, `src-tauri/Cargo.toml`, `src-tauri/Cargo.lock`, `src-tauri/tauri.conf.json`, `src-tauri/src/main.rs`.
- Runtime labels and updater removal: `src-tauri/src/cli.rs`, `src-tauri/src/lib.rs`, `src-tauri/src/tray.rs`, `src-tauri/src/portable.rs`, `src-tauri/src/settings.rs`, `src-tauri/src/shortcut/mod.rs`, `src-tauri/capabilities/default.json`, `src-tauri/capabilities/desktop.json`, `src-tauri/nsis/installer.nsi`, `src/bindings.ts`, `src/stores/settingsStore.ts`, `src/components/footer/Footer.tsx`, `src/components/settings/debug/DebugSettings.tsx`, `src/components/settings/index.ts`.
- Original UI branding: create `src/components/icons/GigaTypeMark.tsx`, `src/components/icons/GigaTypeLogo.tsx`, and `src-tauri/icons/gigatype.svg`; remove `src/components/icons/HandyHand.tsx` and `src/components/icons/HandyTextLogo.tsx`; regenerate `src-tauri/icons/**`.
- User-facing copy and links: `src/components/Sidebar.tsx`, `src/components/onboarding/Onboarding.tsx`, `src/components/onboarding/AccessibilityOnboarding.tsx`, `src/components/settings/about/AboutSettings.tsx`, `src/components/settings/debug/KeyboardImplementationSelector.tsx`, `src/i18n/locales/*/translation.json`, `src/content/release-notes/0.9.0.md`, `src-tauri/src/llm_client.rs`, `src-tauri/src/settings.rs`, `src-tauri/resources/licenses/THIRD_PARTY_NOTICES-CUDA.txt`.
- Windows package tooling: `scripts/build-windows-cuda.ps1`, `scripts/verify-windows-cuda.ps1`, `scripts/test-build-windows-cuda.ps1`, `scripts/test-verify-windows-cuda.ps1`, `.github/workflows/build.yml`.
- Friend/developer documentation: `README.md`, `BUILD.md`, `AGENTS.md`.
- Branding contract: create `tests/gigatype-branding.test.ts`.

---

### Task 1: Commit the approved GigaAM/CUDA baseline

**Files:**
- Commit: every currently modified or untracked implementation file shown by `git status --short`, excluding the already committed design and this implementation plan.

**Interfaces:**
- Consumes: existing GigaAM model catalog IDs, `ModelSource::HuggingFaceBundle`, ONNX accelerator settings, and Windows package scripts already present in the working tree.
- Produces: one buildable baseline commit before branding changes, preserving all user-approved work.

- [ ] **Step 1: Confirm only approved paths are dirty**

Run:

```powershell
git status --short
git diff --stat
```

Expected: only the approved GigaAM/CUDA/Clippy paths, Windows scripts, tests, `BUILD.md`, workflow, and license notices appear. `dist/` and model files do not appear.

- [ ] **Step 2: Re-run focused frontend tests**

Run:

```powershell
bun test tests/model-source.test.ts tests/dropdown-accessibility.test.tsx
```

Expected: `2 pass`, `0 fail`.

- [ ] **Step 3: Re-run source gates**

Run each command separately:

```powershell
bun run build
bun run lint
bun run format:check
cargo test --manifest-path src-tauri/Cargo.toml
cargo clippy --manifest-path src-tauri/Cargo.toml --all-targets -- -D warnings
```

Expected: frontend build/lint/format pass; Rust suite passes with the repository's one ignored test; Clippy exits `0` with no warning.

- [ ] **Step 4: Stage the explicitly approved complete baseline**

Run:

```powershell
git add --all
git diff --cached --check
git diff --cached --stat
```

Expected: all approved feature files are staged; no `dist/`, downloaded model, installer, cache, or credential file is staged.

- [ ] **Step 5: Commit the baseline**

Run:

```powershell
git commit -m "feat: add GigaAM multilingual CUDA support"
```

Expected: commit succeeds and `git status --short` is empty.

### Task 2: Establish GigaType package identity and remove updater coupling

**Files:**
- Create: `tests/gigatype-branding.test.ts`
- Modify: `package.json`, `bun.lock`, `src-tauri/Cargo.toml`, `src-tauri/Cargo.lock`, `src-tauri/tauri.conf.json`, `src-tauri/src/main.rs`, `src-tauri/src/cli.rs`, `src-tauri/src/lib.rs`, `src-tauri/src/tray.rs`, `src-tauri/src/portable.rs`, `src-tauri/src/settings.rs`, `src-tauri/src/shortcut/mod.rs`, `src-tauri/capabilities/default.json`, `src-tauri/capabilities/desktop.json`, `src-tauri/nsis/installer.nsi`, `src/bindings.ts`, `src/stores/settingsStore.ts`, `src/components/footer/Footer.tsx`, `src/components/settings/debug/DebugSettings.tsx`, `src/components/settings/index.ts`
- Delete: `src/components/settings/UpdateChecksToggle.tsx`, `src/components/update-checker/UpdateChecker.tsx`, `src/components/update-checker/index.ts`

**Interfaces:**
- Consumes: Tauri product/bundle configuration and tauri-specta command export.
- Produces: package `gigatype`, binary `GigaType.exe`, library crate `gigatype_app_lib`, CLI command `gigatype`, independent app-data identity, and no callable updater path.

- [ ] **Step 1: Write failing identity tests**

Create `tests/gigatype-branding.test.ts`:

```typescript
import { describe, expect, test } from "bun:test";
import { existsSync, readFileSync } from "node:fs";
import { join } from "node:path";

const root = join(import.meta.dir, "..");
const read = (path: string) => readFileSync(join(root, path), "utf8");

describe("GigaType branding contract", () => {
  test("uses an independent package and bundle identity", () => {
    const tauri = JSON.parse(read("src-tauri/tauri.conf.json"));
    const packageJson = JSON.parse(read("package.json"));
    const cargo = read("src-tauri/Cargo.toml");

    expect(tauri.productName).toBe("GigaType");
    expect(tauri.version).toBe("0.9.3-gigatype.1");
    expect(tauri.identifier).toBe("io.github.ubranch.gigatype");
    expect(tauri.bundle.createUpdaterArtifacts).toBe(false);
    expect(tauri.bundle.windows.signCommand).toBeUndefined();
    expect(packageJson.name).toBe("gigatype-app");
    expect(packageJson.version).toBe("0.9.3-gigatype.1");
    expect(cargo).toContain('name = "gigatype"');
    expect(cargo).toContain('name = "gigatype_app_lib"');
  });

  test("contains no upstream updater integration", () => {
    const packageJson = read("package.json");
    const cargo = read("src-tauri/Cargo.toml");
    const backend = read("src-tauri/src/lib.rs");
    const defaultCapability = read("src-tauri/capabilities/default.json");
    const desktopCapability = read("src-tauri/capabilities/desktop.json");

    expect(packageJson).not.toContain("@tauri-apps/plugin-updater");
    expect(cargo).not.toContain("tauri-plugin-updater");
    expect(backend).not.toContain("tauri_plugin_updater");
    expect(backend).not.toContain("trigger_update_check");
    expect(defaultCapability).not.toContain("updater:");
    expect(desktopCapability).not.toContain("updater:");
    expect(existsSync(join(root, "src/components/update-checker"))).toBe(false);
  });
});
```

- [ ] **Step 2: Run tests and confirm the current Handy identity fails**

Run:

```powershell
bun test tests/gigatype-branding.test.ts
```

Expected: failure showing `Handy` where `GigaType` is expected and updater dependencies still present.

- [ ] **Step 3: Change package and bundle identity**

Apply these exact values:

```json
{
  "name": "gigatype-app",
  "version": "0.9.3-gigatype.1"
}
```

```toml
[package]
name = "gigatype"
version = "0.9.3-gigatype.1"
description = "GigaType"
authors = ["cjpais", "ubranch"]
default-run = "gigatype"

[lib]
name = "gigatype_app_lib"
crate-type = ["staticlib", "cdylib", "rlib"]
```

```json
{
  "productName": "GigaType",
  "version": "0.9.3-gigatype.1",
  "identifier": "io.github.ubranch.gigatype"
}
```

Set `bundle.createUpdaterArtifacts` to `false`; remove `bundle.windows.signCommand`; remove the complete `plugins.updater` object. Change `src-tauri/src/main.rs` imports and calls from `handy_app_lib` to `gigatype_app_lib`.

- [ ] **Step 4: Remove updater execution and settings paths**

Delete these exact integration points:

- `tauri-plugin-updater` and `@tauri-apps/plugin-updater` dependencies.
- `.plugin(tauri_plugin_updater::Builder::new().build())`.
- `trigger_update_check`, `change_update_checks_setting`, the `check_updates` tray handler/menu item, and their specta command registrations.
- `Settings.update_checks_enabled`, its default function/value, store updater, debug toggle, frontend update checker, and `updater:default` capabilities.

Keep `show_whats_new_on_update`; it controls bundled local release notes and does not contact a server.

- [ ] **Step 5: Replace runtime identity strings**

Use these exact public values:

```rust
#[command(name = "gigatype", about = "GigaType - Speech to Text")]
```

```rust
format!("GigaType v{} (Dev)", env!("CARGO_PKG_VERSION"))
format!("GigaType v{}", env!("CARGO_PKG_VERSION"))
```

```rust
.title("GigaType")
```

Replace every public portable marker with `GigaType Portable Mode` in Rust and NSIS. Internal `HandyKeys` identifiers remain unchanged.

- [ ] **Step 6: Regenerate lockfiles and bindings**

Run:

```powershell
bun install
cargo check --manifest-path src-tauri/Cargo.toml
cargo run --manifest-path src-tauri/Cargo.toml -- --list-accelerators --json
```

Expected: lockfiles contain root package `gigatype`; headless command exits `0`, emits accelerator JSON, and regenerates `src/bindings.ts` without updater commands/settings.

- [ ] **Step 7: Verify and commit core identity**

Run:

```powershell
bun test tests/gigatype-branding.test.ts
bun run build
cargo test --manifest-path src-tauri/Cargo.toml
git diff --check
git add package.json bun.lock src-tauri/Cargo.toml src-tauri/Cargo.lock src-tauri/tauri.conf.json src-tauri/src/main.rs src-tauri/src/cli.rs src-tauri/src/lib.rs src-tauri/src/tray.rs src-tauri/src/portable.rs src-tauri/src/settings.rs src-tauri/src/shortcut/mod.rs src-tauri/capabilities/default.json src-tauri/capabilities/desktop.json src-tauri/nsis/installer.nsi src/bindings.ts src/stores/settingsStore.ts src/components/footer/Footer.tsx src/components/settings/debug/DebugSettings.tsx src/components/settings/index.ts src/components/settings/UpdateChecksToggle.tsx src/components/update-checker tests/gigatype-branding.test.ts
git commit -m "feat: establish GigaType application identity"
```

Expected: tests/build pass; commit records renames, deletions, generated locks, and updater isolation.

### Task 3: Replace upstream visual and user-facing branding

**Files:**
- Create: `src/components/icons/GigaTypeMark.tsx`, `src/components/icons/GigaTypeLogo.tsx`, `src-tauri/icons/gigatype.svg`
- Modify: `src/components/Sidebar.tsx`, `src/components/onboarding/Onboarding.tsx`, `src/components/onboarding/AccessibilityOnboarding.tsx`, `src/components/settings/about/AboutSettings.tsx`, `src/components/settings/debug/KeyboardImplementationSelector.tsx`, `src/i18n/locales/*/translation.json`, `src/content/release-notes/0.9.0.md`, `src-tauri/src/llm_client.rs`, `src-tauri/src/settings.rs`, `src-tauri/icons/**`, `tests/gigatype-branding.test.ts`
- Delete: `src/components/icons/HandyHand.tsx`, `src/components/icons/HandyTextLogo.tsx`

**Interfaces:**
- Consumes: existing `--color-logo-primary` and `--color-logo-stroke` theme variables.
- Produces: original GigaType desktop icon, reusable `GigaTypeMark`/`GigaTypeLogo`, and GigaType copy in every locale.

- [ ] **Step 1: Extend branding tests for UI assets and links**

Add this test to `tests/gigatype-branding.test.ts`:

```typescript
  test("uses independent user-facing visuals and links", () => {
    const sidebar = read("src/components/Sidebar.tsx");
    const about = read("src/components/settings/about/AboutSettings.tsx");
    const headers = read("src-tauri/src/llm_client.rs");

    expect(existsSync(join(root, "src/components/icons/GigaTypeMark.tsx"))).toBe(true);
    expect(existsSync(join(root, "src/components/icons/GigaTypeLogo.tsx"))).toBe(true);
    expect(existsSync(join(root, "src/components/icons/HandyHand.tsx"))).toBe(false);
    expect(existsSync(join(root, "src/components/icons/HandyTextLogo.tsx"))).toBe(false);
    expect(sidebar).toContain("GigaTypeLogo");
    expect(sidebar).toContain("GigaTypeMark");
    expect(about).toContain("https://github.com/ubranch/GigaType");
    expect(about).not.toContain("handy.computer/donate");
    expect(headers).toContain("https://github.com/ubranch/GigaType");
  });
```

Run `bun test tests/gigatype-branding.test.ts`; expected failure: GigaType visual files do not exist.

- [ ] **Step 2: Create reusable original logo components**

Create `src/components/icons/GigaTypeMark.tsx`:

```tsx
/* eslint-disable i18next/no-literal-string */
interface GigaTypeMarkProps {
  width?: number | string;
  height?: number | string;
  className?: string;
}

const GigaTypeMark = ({
  width = 126,
  height = 126,
  className,
}: GigaTypeMarkProps) => (
  <svg
    width={width}
    height={height}
    className={className}
    viewBox="0 0 128 128"
    role="img"
    aria-label="GigaType"
    xmlns="http://www.w3.org/2000/svg"
  >
    <rect x="8" y="8" width="112" height="112" rx="30" fill="var(--color-logo-primary)" />
    <path
      d="M84 43a32 32 0 1 0 4 42V66H65"
      fill="none"
      stroke="var(--color-logo-stroke)"
      strokeWidth="10"
      strokeLinecap="round"
      strokeLinejoin="round"
    />
    <path
      d="M43 57v14M53 51v26M63 57v14"
      fill="none"
      stroke="var(--color-logo-stroke)"
      strokeWidth="5"
      strokeLinecap="round"
    />
  </svg>
);

export default GigaTypeMark;
```

Create `src/components/icons/GigaTypeLogo.tsx`:

```tsx
/* eslint-disable i18next/no-literal-string */
import GigaTypeMark from "./GigaTypeMark";

interface GigaTypeLogoProps {
  width?: number;
  height?: number;
  className?: string;
}

const GigaTypeLogo = ({ width = 200, height, className }: GigaTypeLogoProps) => (
  <div
    className={`flex items-center gap-2 ${className ?? ""}`}
    style={{ width, height }}
    role="img"
    aria-label="GigaType"
  >
    <GigaTypeMark width="28%" height="auto" />
    <span className="text-xl font-bold tracking-tight text-text">GigaType</span>
  </div>
);

export default GigaTypeLogo;
```

Replace imports/usages in Sidebar and onboarding components, then delete both upstream logo component files.

- [ ] **Step 3: Create and generate desktop/mobile icon assets**

Create `src-tauri/icons/gigatype.svg`:

```svg
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024">
  <defs>
    <linearGradient id="bg" x1="128" y1="96" x2="896" y2="928" gradientUnits="userSpaceOnUse">
      <stop stop-color="#F59AC4"/>
      <stop offset="1" stop-color="#B85BE8"/>
    </linearGradient>
  </defs>
  <rect width="1024" height="1024" rx="240" fill="url(#bg)"/>
  <path d="M690 338A264 264 0 1 0 724 684V526H532" fill="none" stroke="#2D1F2A" stroke-width="82" stroke-linecap="round" stroke-linejoin="round"/>
  <path d="M356 454v116M434 408v208M512 454v116" fill="none" stroke="#2D1F2A" stroke-width="42" stroke-linecap="round"/>
</svg>
```

Run:

```powershell
bun run tauri icon src-tauri/icons/gigatype.svg --output src-tauri/icons
```

Expected: Tauri regenerates PNG, ICO, ICNS, iOS, and Android icon assets from the new SVG.

- [ ] **Step 4: Replace public copy and network identity**

Apply exact values:

- About source URL: `https://github.com/ubranch/GigaType`; remove upstream donation button/handler.
- Debug keyboard label: `Native Keys`; serialized value remains `handy_keys`.
- OpenRouter headers: `HTTP-Referer=https://github.com/ubranch/GigaType`, `User-Agent=GigaType/1.0 (+https://github.com/ubranch/GigaType)`, `X-Title=GigaType`.
- Default custom words: `["GigaType", "GigaAM"]`.
- CUDA notice title: `GigaType CUDA 13 edition — third-party runtime notices`.

Mechanically replace brand tokens in translation files without translating the proper noun:

```powershell
$utf8 = [System.Text.UTF8Encoding]::new($false)
Get-ChildItem src/i18n/locales -Recurse -Filter translation.json | ForEach-Object {
  $text = [System.IO.File]::ReadAllText($_.FullName)
  if ($text.Contains("Handy")) {
    [System.IO.File]::WriteAllText($_.FullName, $text.Replace("Handy", "GigaType"), $utf8)
  }
}
```

Update bundled 0.9.0 release notes to call those features inherited from upstream and point issue reports to `https://github.com/ubranch/GigaType`.

- [ ] **Step 5: Verify and commit visual branding**

Run:

```powershell
bun test tests/gigatype-branding.test.ts
bun run check:translations
bun run lint
bun run build
bun run format:check
rg -n "HandyTextLogo|HandyHand|handy.computer/donate" src src-tauri --glob "!src/bindings.ts"
```

Expected: all checks pass; final `rg` has no matches. Internal `HandyKeys` matches are allowed in a separate broad branding search.

Commit:

```powershell
git add src/components src/i18n src/content/release-notes/0.9.0.md src-tauri/src/llm_client.rs src-tauri/src/settings.rs src-tauri/resources/licenses/THIRD_PARTY_NOTICES-CUDA.txt src-tauri/icons tests/gigatype-branding.test.ts
git commit -m "feat: add independent GigaType branding"
```

### Task 4: Make Windows build and verification tooling product-aware

**Files:**
- Modify: `scripts/build-windows-cuda.ps1`, `scripts/verify-windows-cuda.ps1`, `scripts/test-build-windows-cuda.ps1`, `scripts/test-verify-windows-cuda.ps1`, `.github/workflows/build.yml`, `tests/gigatype-branding.test.ts`

**Interfaces:**
- Consumes: `productName` and `version` from `src-tauri/tauri.conf.json`.
- Produces: deterministic GigaType CPU/CUDA artifact names and audits that locate `GigaType.exe` without hardcoded upstream executable names.

- [ ] **Step 1: Add failing tooling assertions**

Add this test:

```typescript
  test("build tooling derives GigaType artifacts", () => {
    const build = read("scripts/build-windows-cuda.ps1");
    const verify = read("scripts/verify-windows-cuda.ps1");
    const workflow = read(".github/workflows/build.yml");

    expect(build).toContain("$productName");
    expect(build).toContain("$executableName");
    expect(build).not.toContain('Filter "handy.exe"');
    expect(verify).not.toContain('Filter "handy.exe"');
    expect(build).not.toContain('"Handy_${version}');
    expect(verify).not.toContain('"Handy_${version}');
    expect(workflow).toContain('default: "gigatype"');
  });
```

Run `bun test tests/gigatype-branding.test.ts`; expected failure on hardcoded `Handy` artifact/executable values.

- [ ] **Step 2: Derive product metadata once in each PowerShell entrypoint**

After `$repoRoot` resolution, add:

```powershell
$appConfig = Get-Content -LiteralPath (Join-Path $repoRoot "src-tauri\tauri.conf.json") -Raw |
  ConvertFrom-Json
$productName = [string]$appConfig.productName
$version = [string]$appConfig.version
$executableName = "$productName.exe"
if (-not $productName -or -not $version) {
  throw "tauri.conf.json must define productName and version"
}
```

Use `$executableName` in package discovery and rename result property `handy` to `executable`. Generate output names from `$productName`, `$version`, architecture, and edition. Change default cache/audit prefixes to `gigatype-cuda-build`, `gigatype-cuda-verify`, and `gigatype-audit-`.

- [ ] **Step 3: Update workflow runtime audits**

Set workflow `asset-prefix` default to `gigatype`. Read `productName` in Windows package audit, search for `$productName.exe`, and use generic variable `$appExecutable`. Rename temporary Linux AppImage alias from `Handy.AppImage` to `AppUnderTest.AppImage`; do not assume a product filename.

- [ ] **Step 4: Update PowerShell contract tests and run them**

Replace exact-PID messages with `GigaType PID`; assert product metadata parsing and `$executableName` usage.

Run:

```powershell
& ./scripts/test-build-windows-cuda.ps1
& ./scripts/test-verify-windows-cuda.ps1
bun test tests/gigatype-branding.test.ts
& ./scripts/build-windows-cuda.ps1 -Mode Plan -Edition Cuda -Json
& ./scripts/verify-windows-cuda.ps1 -Mode Plan -Json
```

Expected: both PowerShell contract suites pass; JSON plans retain pinned ONNX Runtime/CUDA/cuDNN/model revisions; branding test passes.

- [ ] **Step 5: Commit product-aware tooling**

```powershell
git add scripts .github/workflows/build.yml tests/gigatype-branding.test.ts
git commit -m "build: package GigaType CPU and CUDA editions"
```

Expected: commit succeeds; no generated `dist/` content is staged.

### Task 5: Replace README and finish developer documentation

**Files:**
- Modify: `README.md`, `BUILD.md`, `AGENTS.md`

**Interfaces:**
- Consumes: exact model IDs, package names, release version, scripts, and accelerator behavior implemented above.
- Produces: friend-facing install/use/troubleshooting documentation and reproducible developer build instructions.

- [ ] **Step 1: Rewrite README as the GigaType entry point**

Use this exact section order:

```markdown
# GigaType

> Private, unofficial fork of cjpais/Handy. GigaType preserves upstream MIT attribution and adds GigaAM Multilingual plus verified Windows CUDA packaging. It is not endorsed by or affiliated with upstream Handy.

## What this fork adds
## Download: CPU or CUDA
## Install on Windows
## First transcription
## GigaAM model guide
## RTX 5080 setup
## Accelerator behavior
## Model limitations
## Privacy and model downloads
## Verify SHA256
## Troubleshooting
## Build from source
## Repository layout
## License and upstream attribution
```

Document all four exact asset names. Recommend `GigaAM Multilingual 220M INT8` for CPU, `GigaAM Multilingual 220M FP32 CUDA` for balanced GPU use, and `GigaAM Multilingual 600M FP32 CUDA` for the user's RTX 5080. State supported languages `uz`, `kk`, `ky`, `ru`, `en`; lowercase/no punctuation/no digit vocabulary limitations; model weights download separately from pinned Hugging Face repositories.

Document unsigned Windows warning accurately: verify release SHA256, then use Windows `More info -> Run anyway` only when the hash matches the private release notes.

- [ ] **Step 2: Update BUILD.md with exact commands and outputs**

Use clone URL `https://github.com/ubranch/GigaType.git`, directory `GigaType`, version `0.9.3-gigatype.1`, and the four exact output paths. Include:

```powershell
bun install
& ./scripts/test-build-windows-cuda.ps1
& ./scripts/test-verify-windows-cuda.ps1
& ./scripts/build-windows-cuda.ps1 -Mode All -Edition Cpu
& ./scripts/verify-windows-cuda.ps1 -Mode All -Repeat 3
```

Retain cross-platform source prerequisites, but label Windows x64 as the only packaged release target. Explain cache locations, pinned runtime versions, package audit, CUDA negative-provider test, FLEURS `uz_uz` fixture, WER parity, timing, and exact-PID VRAM proof.

- [ ] **Step 3: Update AGENTS.md operational facts**

Change project description to GigaType, add GigaAM model bundle/CTC and ORT accelerator boundaries, add CPU/CUDA PowerShell validation commands, and state that upstream remote/history/internal `HandyKeys` naming remains intentional.

- [ ] **Step 4: Verify documentation and commit**

Run:

```powershell
rg -n "cjpais/Handy/releases|winget install cjpais.Handy|Handy_0\.9\.3" README.md BUILD.md AGENTS.md
rg -n "GigaType_0\.9\.3-gigatype\.1_x64" README.md BUILD.md
bun run format:check
git diff --check
```

Expected: first search has no stale fork install links/artifacts; second finds all documented CPU/CUDA package names; format/diff checks pass.

Commit:

```powershell
git add README.md BUILD.md AGENTS.md
git commit -m "docs: document GigaType installation and builds"
```

### Task 6: Run final source and branding gates

**Files:**
- Verify: complete committed source tree.
- Modify only when a gate identifies a concrete defect.

**Interfaces:**
- Consumes: Tasks 1-5 commits.
- Produces: source revision eligible for expensive Windows package builds.

- [ ] **Step 1: Run frontend gates**

```powershell
bun test tests/model-source.test.ts tests/dropdown-accessibility.test.tsx tests/gigatype-branding.test.ts
bun run check:translations
bun run build
bun run lint
bun run format:check
```

Expected: all tests and commands pass with exit code `0`.

- [ ] **Step 2: Run Rust gates**

```powershell
cargo fmt --manifest-path src-tauri/Cargo.toml -- --check
cargo test --manifest-path src-tauri/Cargo.toml
cargo clippy --manifest-path src-tauri/Cargo.toml --all-targets -- -D warnings
```

Expected: format passes; Rust tests pass with only the repository's intentional ignored test; Clippy reports no warning.

- [ ] **Step 3: Audit branding exceptions**

```powershell
rg -n "Handy|handy\.exe|com\.pais\.handy|cjpais/Handy/releases/latest" package.json src src-tauri scripts .github README.md BUILD.md AGENTS.md --glob "!src-tauri/src/shortcut/handy_keys.rs" --glob "!src/components/settings/HandyKeysShortcutInput.tsx" --glob "!src/bindings.ts" --glob "!src-tauri/Cargo.lock"
```

Expected matches are limited to upstream attribution, internal/historical comments, dependency URLs, `HandyKeys`, and the design/plan documents. Any shipped label, icon, installer, updater, signing, or friend-facing install match is a failure.

- [ ] **Step 4: Confirm clean, buildable revision**

```powershell
git status --short --branch
git log -5 --oneline
```

Expected: branch `agent/gigatype-private-fork`, no unstaged/staged source changes, and conventional commits for baseline, identity, branding, tooling, and docs. If gate-driven fixes were necessary, commit them with a focused `fix:` message before continuing.

### Task 7: Rebuild and verify final Windows installers

**Files:**
- Generate, do not commit: `dist/windows-cpu/**`, `dist/windows-cuda/**`.

**Interfaces:**
- Consumes: clean source revision and cached pinned native dependencies/models.
- Produces: four final installers, SHA256 values, package audits, CPU smoke proof, CUDA provider proof, transcription parity, performance, and exact RTX 5080 VRAM evidence.

- [ ] **Step 1: Re-run script contract tests**

```powershell
& ./scripts/test-build-windows-cuda.ps1
& ./scripts/test-verify-windows-cuda.ps1
```

Expected: both exit `0` before expensive builds begin.

- [ ] **Step 2: Build and audit CPU installers**

```powershell
& ./scripts/build-windows-cuda.ps1 -Mode All -Edition Cpu -OutputDir ./dist/windows-cpu
```

Expected: CPU NSIS/MSI exist under exact GigaType names; package audit finds no CUDA DLL; packaged `GigaType.exe --list-devices` exits `0`.

- [ ] **Step 3: Build, audit, and benchmark CUDA installers**

```powershell
& ./scripts/verify-windows-cuda.ps1 -Mode All -Repeat 3
```

Expected: CUDA NSIS/MSI exist under exact names; both package formats have complete PE/DLL closure and zero unresolved imports; missing-provider negative test fails clearly; 220M/600M CPU and CUDA transcripts meet WER parity; CUDA is faster; exact GigaType PID shows non-zero RTX 5080 VRAM.

- [ ] **Step 4: Compute final artifact evidence**

```powershell
$assets = @(
  "dist/windows-cpu/GigaType_0.9.3-gigatype.1_x64-setup.exe",
  "dist/windows-cpu/GigaType_0.9.3-gigatype.1_x64_en-US.msi",
  "dist/windows-cuda/GigaType_0.9.3-gigatype.1_x64-cuda13-setup.exe",
  "dist/windows-cuda/GigaType_0.9.3-gigatype.1_x64-cuda13_en-US.msi"
)
$assets | ForEach-Object {
  $file = Get-Item -LiteralPath $_
  $hash = Get-FileHash -LiteralPath $_ -Algorithm SHA256
  [pscustomobject]@{ Name = $file.Name; Bytes = $file.Length; SHA256 = $hash.Hash.ToLowerInvariant() }
} | Format-Table -AutoSize
```

Expected: four rows, non-zero sizes, unique SHA256 values; CUDA assets remain outside Git.

### Task 8: Create private GitHub repository, push source, and publish release

**Files:**
- External writes: GitHub repository `ubranch/GigaType`, branch `main`, release `v0.9.3-gigatype.1`, four assets.
- Local Git metadata: add remote `private`.

**Interfaces:**
- Consumes: clean branch, four verified local artifacts, active `gh` authentication for `ubranch`.
- Produces: private source repository and private non-draft release.

- [ ] **Step 1: Run publication preflight**

```powershell
gh auth status
gh repo view ubranch/GigaType --json nameWithOwner,visibility,url
git remote -v
git status --short
```

Expected: authenticated as `ubranch`; repository lookup returns not found before creation; no `private` remote exists; working tree is clean. Verify current official GitHub Release per-file limit supports the largest local asset before creating external state.

- [ ] **Step 2: Create private repository and preserve upstream remote**

```powershell
gh repo create ubranch/GigaType --private --source=. --remote=private --description "Private GigaType fork with GigaAM Multilingual and Windows CUDA support"
git remote -v
gh repo view ubranch/GigaType --json nameWithOwner,visibility,url
```

Expected: `origin` still points to `cjpais/Handy`; `private` points to `ubranch/GigaType`; visibility is `PRIVATE`.

- [ ] **Step 3: Push reviewed source as private main**

```powershell
git push --set-upstream private HEAD:main
gh api repos/ubranch/GigaType/branches/main --jq '.commit.sha'
git rev-parse HEAD
```

Expected: remote `main` SHA equals local `HEAD`.

- [ ] **Step 4: Create draft release and upload assets**

```powershell
$assets = @(
  "dist/windows-cpu/GigaType_0.9.3-gigatype.1_x64-setup.exe",
  "dist/windows-cpu/GigaType_0.9.3-gigatype.1_x64_en-US.msi",
  "dist/windows-cuda/GigaType_0.9.3-gigatype.1_x64-cuda13-setup.exe",
  "dist/windows-cuda/GigaType_0.9.3-gigatype.1_x64-cuda13_en-US.msi"
)
$hashLines = $assets | ForEach-Object {
  $hash = (Get-FileHash -LiteralPath $_ -Algorithm SHA256).Hash.ToLowerInvariant()
  "- ``$((Get-Item -LiteralPath $_).Name)``: ``$hash``"
}
$notes = @"
Private Windows x64 release of GigaType.

- CPU packages: broad compatibility, no NVIDIA runtime.
- CUDA 13 packages: NVIDIA GPU acceleration; verified on RTX 5080.
- Recommended RTX 5080 model: GigaAM Multilingual 600M FP32 CUDA.
- Models download separately. GigaAM output is lowercase and has no punctuation or digit vocabulary.
- Unsigned installers: proceed only after verifying SHA256 below.

SHA256
$($hashLines -join "`n")
"@
gh release create v0.9.3-gigatype.1 --repo ubranch/GigaType --target main --title "GigaType 0.9.3-gigatype.1" --notes $notes --draft
gh release upload v0.9.3-gigatype.1 --repo ubranch/GigaType $assets
```

Expected: draft release exists and upload completes for all four assets. Keep draft state if any upload fails.

- [ ] **Step 5: Verify remote assets and publish release**

```powershell
gh api repos/ubranch/GigaType/releases/tags/v0.9.3-gigatype.1 --jq '.assets[] | [.name, .size, .digest] | @tsv'
gh release view v0.9.3-gigatype.1 --repo ubranch/GigaType --json isDraft,isPrerelease,url,assets
gh release edit v0.9.3-gigatype.1 --repo ubranch/GigaType --draft=false
gh release view v0.9.3-gigatype.1 --repo ubranch/GigaType --json isDraft,url,assets
```

Expected: exactly four expected names/sizes; every available API `digest` equals the `sha256:` prefix plus its computed local hash; final `isDraft` is `false`. If GitHub omits digest, report that proof limit and compare exact byte sizes instead of claiming remote hash proof.

### Task 9: Grant friend read access

**Files:**
- External write: one GitHub collaborator invitation.

**Interfaces:**
- Consumes: exact friend GitHub username from the user.
- Produces: least-privilege `pull` invitation and friend access to private source/release assets.

- [ ] **Step 1: Request exact GitHub username**

Ask one question: `jo‘rangizning exact GitHub username’i nima?`

Expected: a single account name, confirmed by `gh api users/<username> --jq '.login'`.

- [ ] **Step 2: Send read-only invitation and verify pending/access state**

```powershell
$friend = Read-Host "Friend GitHub username"
$resolvedFriend = gh api "users/$friend" --jq '.login'
if ($resolvedFriend -cne $friend) {
  throw "GitHub username mismatch: requested $friend, resolved $resolvedFriend"
}
$friend = $resolvedFriend
gh api --method PUT "repos/ubranch/GigaType/collaborators/$friend" -f permission=pull
gh api "repos/ubranch/GigaType/collaborators/$friend/permission" --jq '{user: .user.login, permission: .permission}'
```

Expected: invitation succeeds; permission reports `read`/`pull` after acceptance or GitHub reports the invitation as pending. Send the friend private repository/release URL only after this state is known.

## Completion Evidence

- Local branch clean; source gates pass.
- Private `ubranch/GigaType` `main` equals local `HEAD`.
- Release `v0.9.3-gigatype.1` is non-draft and contains exactly four verified installers.
- Final response lists commit SHA, repository URL, release URL, four local/remote sizes and SHA256 values, validation results, unsigned-installer warning, model recommendation, and collaborator invitation state.
