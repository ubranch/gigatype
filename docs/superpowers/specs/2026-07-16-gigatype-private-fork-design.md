# GigaType private fork design

## Goal

Turn the current working tree into a private, friend-ready fork named GigaType. The fork keeps Handy's MIT-licensed source history and attribution, ships the completed GigaAM Multilingual and Windows CUDA work, uses independent public-facing branding, and does not claim upstream endorsement.

## Scope

The release includes every current working-tree change: GigaAM Multilingual 220M and 600M model support, model bundle handling, CPU and CUDA execution selection, Windows CUDA build and verification scripts, accessibility tests, model-source tests, and the approved pre-existing Clippy cleanup. No dirty file is excluded.

The fork is Windows-first for this release. Existing macOS and Linux source support remains, but only Windows x64 CPU and NVIDIA CUDA packages are release-gated and published.

## Repository and Git topology

- GitHub repository: private `ubranch/GigaType`.
- Existing `origin` remains `https://github.com/cjpais/Handy.git` for upstream comparison and future merges.
- New remote is named `private` and points to `https://github.com/ubranch/gigatype.git`.
- Work is committed on `agent/gigatype-private-fork`, then pushed as the new repository's `main` branch.
- The empty private repository receives a direct initial push; no synthetic pull request is created.
- The friend receives least-privilege read access after their GitHub username is provided; write access is out of scope unless separately requested.

## Branding boundary

Public-facing application identity changes from Handy to GigaType:

- Tauri `productName`, bundle identifier, window/tray/CLI labels, installer text, package descriptions, portable marker text, documentation title, and release artifact names use GigaType.
- Bundle identifier becomes `io.github.ubranch.gigatype`, allowing GigaType and upstream Handy to coexist without sharing installation identity.
- A new original GigaType icon replaces Handy logo/icon assets used by desktop bundles. The visual is a simple `G` plus speech-wave motif and is not derived from upstream artwork.
- Upstream signing command and update configuration are removed, and automatic update checks are disabled. Unsigned private releases must never advertise themselves as upstream-signed or consume upstream update metadata.
- Internal implementation identifiers whose renaming adds risk without affecting branding remain unchanged, including `HandyKeys`, Rust module names, historical comments, and upstream dependency URLs.
- README preserves upstream copyright, MIT license, repository provenance, and an explicit unofficial-fork notice.

## Runtime architecture

The transcription flow remains:

`microphone -> VAD/resampling -> selected model backend -> accelerator selection -> transcription -> post-processing -> clipboard/paste`

GigaAM model behavior remains isolated behind the existing model catalog, bundle downloader, and transcription manager boundaries:

- Model catalog exposes GigaAM Multilingual 220M and 600M CTC variants.
- Model bundle layer downloads and materializes required ONNX/vocabulary files.
- Transcription manager selects CPU, CUDA, or Auto without changing model semantics.
- Auto attempts CUDA only when the packaged execution provider is usable; a diagnosed initialization failure falls back to CPU and reports the reason.
- CUDA packages include the audited ONNX Runtime CUDA 13 dependency set; CPU packages remain small and contain no CUDA runtime.

No new cloud service, telemetry, account, or remote transcription path is introduced.

## Documentation

README becomes the friend-facing entry point and covers:

- GigaType's relationship to upstream Handy and exact fork features.
- Windows CPU versus NVIDIA CUDA package selection.
- Installation, Windows unsigned-publisher warning, first launch, microphone permission, shortcut use, and model download.
- Recommended model: 220M for normal use; 600M for maximum Uzbek accuracy on strong hardware.
- RTX 5080 guidance, Auto/CUDA/CPU selection, expected fallback behavior, and VRAM considerations.
- Model files are downloaded separately and are not embedded in installers.
- Troubleshooting for missing CUDA provider/DLLs, model download failure, slow CPU inference, and clean uninstall.
- SHA256 verification commands and release asset checksums.

`BUILD.md` remains the source-build reference and is updated for GigaType repository URLs, product names, versioned artifacts, CPU/CUDA scripts, prerequisites, and verification commands. Upstream-only contribution and release links remain clearly labeled as upstream references or are removed where they would misdirect fork users.

## Release packaging

Release version and tag are fixed at `0.9.3-gigatype.1` and `v0.9.3-gigatype.1`. A bundler incompatibility is a build failure to fix, not permission to silently change the version.

Four Windows x64 assets are published in a private GitHub Release:

- `GigaType_0.9.3-gigatype.1_x64-setup.exe` (CPU NSIS).
- `GigaType_0.9.3-gigatype.1_x64_en-US.msi` (CPU MSI).
- `GigaType_0.9.3-gigatype.1_x64-cuda13-setup.exe` (CUDA 13 NSIS).
- `GigaType_0.9.3-gigatype.1_x64-cuda13_en-US.msi` (CUDA 13 MSI).

Installer binaries are never committed to Git because each CUDA artifact exceeds GitHub's normal Git object limit. Release notes include package selection, requirements, known punctuation/digit limitations inherited from the model, and SHA256 values generated from final rebuilt artifacts.

## Failure handling

- Missing model files fail with an actionable model-download error; no silent substitute model is selected.
- Explicit CUDA mode fails clearly when CUDA cannot initialize. Auto mode may fall back to CPU only with a recorded diagnostic reason.
- Release publication stops if any final artifact is absent, hashes do not match, package audit finds unresolved DLLs, or source validation fails.
- GitHub repository/release creation stops on authentication, permission, asset-size, or upload errors; partial external state is reported rather than hidden.
- Collaborator invitation is a separate final action and requires an exact GitHub username.

## Validation and acceptance criteria

Source gates:

- Frontend build, ESLint, Prettier check, focused Bun tests, Rust tests, `cargo fmt --check`, and Clippy with warnings denied pass from the final source tree.
- Branding search confirms no shipped UI, installer, updater, signing, or friend-facing documentation presents the application as Handy. Allowed matches are internal API identifiers, historical attribution, dependency URLs, and upstream references.

Windows package gates:

- CPU and CUDA NSIS/MSI packages rebuild from the final GigaType source revision.
- CPU package smoke test passes without CUDA runtime dependencies.
- CUDA verifier confirms expected DLL inventory, no unresolved PE imports, usable CUDA provider, exact RTX 5080 process attribution, and successful 220M/600M CPU-versus-CUDA transcription parity.
- Installed application reports GigaType identity and can coexist with Handy.
- Final GitHub Release hashes equal hashes computed from uploaded local artifacts.

Delivery is complete when private `ubranch/GigaType` contains the documented source revision on `main`, the private release contains all four verified installers, and the selected collaborator can access the repository and release.

## Explicit non-goals

- Public marketing, website, store listing, auto-update infrastructure, or code signing.
- Rewriting internal upstream history or renaming every `Handy` implementation symbol.
- Publishing model weights inside Git or installer assets.
- Opening a pull request against upstream Handy.
