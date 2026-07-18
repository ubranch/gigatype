# AGENTS.md

this file defines repository-specific guidance for coding agents working on GigaType.

## Product identity and provenance

GigaType is a private, unofficial fork of `cjpais/Handy`. public application, installer, repository, and documentation surfaces use `GigaType`; the source remains MIT-licensed and preserves upstream copyright and Git history.

- repository: `https://github.com/ubranch/gigatype.git`
- current release version: `0.9.3-gigatype.2`
- Tauri identifier: `io.github.ubranch.gigatype`
- Windows executable: `GigaType.exe`
- packaged release target: Windows x64 only, in separate CPU and CUDA 13 editions
- source-development targets: Windows, macOS, and Linux

the `origin` remote intentionally remains `https://github.com/cjpais/Handy.git` for upstream comparison and future history integration. do not rewrite upstream history or casually repoint `origin`.

historical/internal names may remain when they are not shipped branding. `HandyKeys`, `HandyKeysShortcutInput`, serialized `handy_keys`, selected `HANDY_*` compatibility environment variables, dependency URLs, and historical comments are intentional implementation details. do not mechanically rename them without a scoped migration and compatibility proof.

## Development commands

prerequisites are current stable Rust, Bun, and the official Tauri platform prerequisites. see [BUILD.md](BUILD.md) for full platform and package requirements.

```powershell
bun install
bun run tauri dev
bun run build
bun run lint
bun run format:check
cargo fmt --manifest-path src-tauri/Cargo.toml -- --check
cargo test --manifest-path src-tauri/Cargo.toml
cargo clippy --manifest-path src-tauri/Cargo.toml --all-targets -- -D warnings
```

do not run an expensive production/package build unless the task requires package proof.

### Windows CPU validation

```powershell
& ./scripts/test-build-windows-cuda.ps1
& ./scripts/build-windows-cuda.ps1 -Mode Plan -Edition Cpu -Json
& ./scripts/build-windows-cuda.ps1 -Mode All -Edition Cpu
```

expected package paths:

- `dist/windows-cpu/GigaType_0.9.3-gigatype.2_x64-setup.exe`
- `dist/windows-cpu/GigaType_0.9.3-gigatype.2_x64_en-US.msi`

### Windows CUDA validation

```powershell
& ./scripts/test-build-windows-cuda.ps1
& ./scripts/test-verify-windows-cuda.ps1
& ./scripts/build-windows-cuda.ps1 -Mode Plan -Edition Cuda -Json
& ./scripts/verify-windows-cuda.ps1 -Mode Plan -Json
& ./scripts/verify-windows-cuda.ps1 -Mode All -Repeat 3
```

expected package paths:

- `dist/windows-cuda/GigaType_0.9.3-gigatype.2_x64-cuda13-setup.exe`
- `dist/windows-cuda/GigaType_0.9.3-gigatype.2_x64-cuda13_en-US.msi`

contract tests and `Plan` mode prove configuration and command contracts only; they provide no package or runtime proof. `scripts/build-windows-cuda.ps1 -Mode Audit` proves package content for supplied artifacts. `scripts/verify-windows-cuda.ps1 -Mode Verify` proves runtime behavior for supplied installers. build-script `All` builds and audits the selected edition; verifier `All` builds, audits, and verifies the CUDA edition end to end. all evidence applies only to the exact artifacts and machine tested.

## Architecture

GigaType is a Tauri 2 desktop application with a Rust backend and React/TypeScript frontend.

```text
microphone -> VAD/resampling -> selected model backend -> accelerator -> transcription -> optional post-processing -> clipboard/paste
```

key backend locations:

- `src-tauri/src/lib.rs`: Tauri setup, managed state, commands, and plugins
- `src-tauri/src/managers/audio.rs`: device and recording management
- `src-tauri/src/managers/model.rs`: model catalog, downloads, selection, and migration
- `src-tauri/src/managers/model_bundle.rs`: verified multi-file bundle materialization
- `src-tauri/src/managers/transcription.rs`: backend loading, ORT selection, diagnostics, and transcription
- `src-tauri/src/settings.rs`: persisted settings and defaults
- `src-tauri/src/shortcut/`: shortcut backends and runtime controls
- `src-tauri/src/signal_handle.rs`: shared transcription command path

key frontend locations:

- `src/App.tsx`: application root and onboarding
- `src/components/model-selector/`: model selection/download UI
- `src/components/settings/`: settings UI
- `src/stores/`: Zustand state and Tauri command integration
- `src/bindings.ts`: generated tauri-specta bindings; regenerate from the Rust command export path rather than hand-editing
- `src/i18n/locales/en/translation.json`: source locale for user-facing strings

## GigaAM catalog and bundle boundary

the four supported multilingual entries are registered in `src-tauri/src/managers/model.rs`:

- `gigaam-multilingual-220m-int8` / `GigaAM Multilingual 220M INT8`
- `gigaam-multilingual-220m-fp32-cuda` / `GigaAM Multilingual 220M FP32 CUDA`
- `gigaam-multilingual-600m-int8` / `GigaAM Multilingual 600M INT8`
- `gigaam-multilingual-600m-fp32-cuda` / `GigaAM Multilingual 600M FP32 CUDA`

all four are `EngineType::GigaAM`, use `ModelSource::HuggingFaceBundle`, and support `uz`, `kk`, `ky`, `ru`, and `en`. they are non-streaming CTC models with automatic language detection and no manual language-selection contract. raw output has no punctuation or digit vocabulary.

the 220M files are pinned to `istupakov/gigaam-multilingual-ctc-onnx` revision `458860e1983aef670dd9795fb6af603c82767d5d`; 600M files are pinned to `istupakov/gigaam-multilingual-large-ctc-onnx` revision `07665ab5e54371dd1ac7b8b10f06478003723573`.

each bundle declares every remote/local filename, expected byte count, and SHA256, including `multilingual_vocab.txt` materialized as `vocab.txt`. `model_bundle.rs` owns staging, cancellation cleanup, verification, and completed-bundle exposure. do not bypass it with a raw URL, trust an unpinned branch, silently substitute a file/model, or mark a partially materialized directory downloaded.

model weights are runtime downloads. they must never enter Git, installers, `src-tauri/resources`, or release source archives.

## CTC and inference boundary

GigaAM inference is ONNX CTC through `transcribe-rs`; model and vocabulary paths are supplied together. model download/catalog code must not implement decoding, and UI code must not infer bundle layout.

Whisper-family GGML/GGUF models use `transcribe-cpp`. its native `Auto`/`CPU`/`GPU` backend and device selection are separate from ONNX Runtime. do not route Whisper through ORT or assume the ORT accelerator changes a `transcribe-cpp` model.

## ONNX Runtime accelerator boundary

`OrtAcceleratorSetting` controls ONNX models such as GigaAM, Parakeet, Moonshine, SenseVoice, Canary, and Cohere.

- `Auto` selects CUDA only when CUDA support is compiled into this Windows x64 build and provider registration succeeds; otherwise it selects CPU and preserves a diagnostic fallback reason.
- `CPU` forces `transcribe_rs::OrtAccelerator::CpuOnly`.
- explicit `CUDA` is strict. missing app-local DLLs, provider-registration failure, or missing/incompatible NVIDIA driver returns an error rather than silently using CPU.
- the default/CPU build does not compile `ort-cuda`; the CUDA package builds with `--features ort-cuda` and stages its provider/runtime beside `GigaType.exe`.

accelerator preference is applied before model load. changing it requires the model to reload on next use. preserve process-only CLI override semantics and the `--list-accelerators --json` diagnostics contract.

## Windows package boundary

`scripts/build-windows-cuda.ps1` derives product/version/executable names from `src-tauri/tauri.conf.json`; do not reintroduce hardcoded upstream artifact names.

CPU and CUDA packages share application code but not native runtime inventory:

- CPU packages stage CPU ONNX Runtime, reject CUDA/NVIDIA files, include ONNX Runtime license/notices, and launch packaged device diagnostics.
- CUDA packages stage pinned ONNX Runtime CUDA 13, CUDA 13.0 Update 2 components, and cuDNN 9.16.0.29; require their licenses/notices, zero unresolved PE imports, usable explicit CUDA diagnostics, transcript parity/timing gates, and exact-PID VRAM proof.
- neither edition contains model weights.
- both editions are unsigned. upstream signing/updater configuration must remain absent; release consumers verify SHA256 from private release notes.

package caches and `dist/` are generated state. never commit installers, extracted runtimes, model files, caches, benchmark evidence, or credentials.

## Commands and process control

supported CLI flags include:

- `--toggle-transcription`, `--toggle-post-process`, and `--cancel` for the running single instance
- `--start-hidden`, `--no-tray`, and `--debug`
- `--list-devices`, `--list-accelerators`, `--device-index`, `--ort-accelerator`, `--transcribe-file`, `--model`, `--repeat`, and `--json` for diagnostics/verification

runtime-only flags do not modify persisted settings. remote-control flags are delivered through `tauri_plugin_single_instance` and the second process exits.

before starting a development server, inspect port `1420` and existing Tauri/Vite processes. identify the exact PID before stopping any process.

## Internationalization and generated files

all user-facing JSX strings use i18next. add or change English keys in `src/i18n/locales/en/translation.json`, update every locale, then run:

```powershell
bun run check:translations
bun run lint
```

do not hand-edit generated icon mirrors or `src/bindings.ts` without following their source-of-truth generation path. verify generated changes before committing.

## Code style and validation

Rust code uses explicit errors in production paths, scoped expected-error handling, and no silent dependency/model fallback. TypeScript remains strict and avoids `any`. preserve dirty worktrees and change only task-owned files.

before commit, run the narrow tests for changed behavior plus relevant format/lint/type/Rust checks. use `git diff --check` and inspect the staged allowlist. distinguish source checks, local package proof, and deployed/release proof in every handoff.

## Licensing and attribution

preserve root MIT text and `Copyright (c) 2025 CJ Pais`. keep the unofficial-fork and no-upstream-endorsement notice in friend-facing documentation. model weights retain their model-repository terms and are not relicensed by the source MIT license.

Windows package code must continue staging ONNX Runtime license/notices. CUDA packages must also stage official CUDA/cuDNN license files and `src-tauri/cuda-resources/THIRD_PARTY_NOTICES-CUDA.txt`.

## GitHub workflow

before opening a PR, issue, or discussion, read and follow the relevant `.github` template. conventional commit prefixes are required. never add `Co-authored-by: Claude Code`.
