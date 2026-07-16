# GigaType

> Private, unofficial fork of cjpais/Handy. GigaType preserves upstream MIT attribution and adds GigaAM Multilingual plus verified Windows CUDA packaging. It is not endorsed by or affiliated with upstream Handy.

GigaType is a local desktop speech-to-text application: press a shortcut, speak, and paste the transcription into the focused text field. version `0.9.3-gigatype.1` targets separate CPU and NVIDIA CUDA 13 packages for Windows x64.

## What this fork adds

- four pinned GigaAM Multilingual CTC choices covering `uz`, `kk`, `ky`, `ru`, and `en`
- Windows x64 CPU and NVIDIA CUDA 13 packaging, with package-content and execution-provider audits
- explicit `Auto`, `CPU`, and `CUDA` behavior for ONNX Runtime models
- independent GigaType application identity, with upstream source history and MIT attribution preserved
- no upstream updater or signing identity; private installers are unsigned and updates are installed manually

speech recognition, VAD, history, and text insertion run locally. installers do not contain GigaAM weights; selecting a model downloads its pinned files separately.

## Download: CPU or CUDA

when release `0.9.3-gigatype.1` is published, it targets the four Windows x64 assets below. no packaged release is planned for other platforms.

| edition | installer                                        | use it when                                                      |
| ------- | ------------------------------------------------ | ---------------------------------------------------------------- |
| CPU     | `GigaType_0.9.3-gigatype.1_x64-setup.exe`        | recommended for systems without a supported NVIDIA GPU           |
| CPU     | `GigaType_0.9.3-gigatype.1_x64_en-US.msi`        | same CPU application in MSI format                               |
| CUDA 13 | `GigaType_0.9.3-gigatype.1_x64-cuda13-setup.exe` | NVIDIA GPU package with app-local ONNX Runtime CUDA 13 libraries |
| CUDA 13 | `GigaType_0.9.3-gigatype.1_x64-cuda13_en-US.msi` | same CUDA application in MSI format                              |

choose one package format and one edition. the CPU edition is smaller and does not include CUDA runtime libraries. the CUDA edition requires a compatible NVIDIA display driver; CUDA developer tools are not required.

when published, the four assets will be distributed with the private GigaType release. access requires permission to the private repository.

## Install on Windows

1. after the private release is published, download one installer and find its SHA256 in the matching release notes.
2. verify the local file with the command in [Verify SHA256](#verify-sha256). stop if the values differ.
3. run the `.exe` setup or `.msi`; do not install both formats.
4. installers published by this private fork are unsigned, so Windows may show an unknown-publisher or Microsoft Defender SmartScreen warning. only after the SHA256 matches, select `More info -> Run anyway` when that option is shown.
5. launch GigaType. on the Windows onboarding microphone card, select `Open Settings`. in `Settings -> Privacy & security -> Microphone`, enable `Microphone access` and `Let desktop apps access your microphone`, then return to GigaType. repeat this settings step until onboarding shows the permission as granted.

GigaType has no automatic updater. verify and install a newer private package manually when one is published.

## First transcription

1. open GigaType and complete the Windows microphone onboarding described above.
2. in onboarding or the model selector, click `Show all models` before choosing a GigaAM entry; GigaAM models are not shown among the recommended cards.
3. download and select `GigaAM Multilingual 220M INT8` on CPU, or the matching GPU recommendation below. wait until the model is marked downloaded.
4. `Auto` is the default ONNX Runtime accelerator. to inspect or change it, open `Settings -> Advanced`, enable `Experimental Features`, then under `Experimental` use `ONNX Acceleration`. choose `CPU` or `CUDA` explicitly only when needed for the selected edition or diagnostics.
5. the default Windows transcription shortcut is `Ctrl+Space`, with push-to-talk enabled. configure either setting if that workflow is not convenient.
6. focus a text field, hold the shortcut while speaking, then release it. if push-to-talk is disabled, press once to start and once to stop. GigaType transcribes locally and inserts the result into the focused application.

the first model selection needs network access because model weights are not embedded in the installer.

## GigaAM model guide

| model                                | intended use                                                                        |                                 download size |
| ------------------------------------ | ----------------------------------------------------------------------------------- | --------------------------------------------: |
| `GigaAM Multilingual 220M INT8`      | recommended CPU model                                                               |                 about 214 MiB plus vocabulary |
| `GigaAM Multilingual 220M FP32 CUDA` | recommended balanced GPU model                                                      |                 about 844 MiB plus vocabulary |
| `GigaAM Multilingual 600M INT8`      | larger CPU model; use only when its extra memory and processing cost are acceptable |                 about 564 MiB plus vocabulary |
| `GigaAM Multilingual 600M FP32 CUDA` | recommended RTX 5080 model                                                          | about 2.18 GiB plus ONNX graph and vocabulary |

all four are multilingual CTC models for `uz`, `kk`, `ky`, `ru`, and `en`. `220M INT8` is the default recommendation for CPU use; `220M FP32 CUDA` balances GPU download size and model capacity; `600M FP32 CUDA` is the RTX 5080 recommendation.

## RTX 5080 setup

1. install either CUDA 13 asset, after verifying its SHA256.
2. install a compatible current NVIDIA display driver. the GigaType package supplies ONNX Runtime, CUDA 13.0 Update 2 runtime components, and cuDNN 9.16.0.29 beside the application; it does not supply the driver.
3. download and select `GigaAM Multilingual 600M FP32 CUDA`.
4. use `Auto` for normal operation. use explicit `CUDA` when you want startup/model-load failure instead of CPU fallback if CUDA is unavailable.
5. inspect provider state from the GigaType installation directory when needed:

```powershell
& .\GigaType.exe --list-accelerators --json
```

the repository verifier can measure CUDA timing and exact-process VRAM use, but this README does not promise a fixed speed or VRAM figure for every driver, audio sample, or machine.

## Accelerator behavior

GigaAM and other ONNX models use the ONNX Runtime (`ORT`) accelerator setting. Whisper-family GGML/GGUF models use the separate `transcribe-cpp` accelerator setting, so changing ORT does not select a Whisper backend.

- `Auto`: uses CUDA only when this Windows x64 build includes CUDA support and the CUDA execution provider registers successfully. otherwise it selects CPU and records the diagnostic reason.
- `CPU`: forces ONNX inference onto CPU.
- `CUDA`: requires usable CUDA support. missing app-local runtime files, provider registration failure, or an incompatible/missing NVIDIA driver causes a clear error; explicit CUDA does not silently continue on CPU.

the CPU package is built without the CUDA execution provider. the CUDA package carries an audited app-local CUDA dependency set. package verification checks that CPU installers contain no CUDA runtime and CUDA installers contain the required provider/runtime files.

## Model limitations

- supported languages are `uz`, `kk`, `ky`, `ru`, and `en`; other languages are outside this model bundle's contract.
- output is lowercase with little or no punctuation.
- the vocabulary has no digit tokens, so do not expect numeric digits in raw GigaAM output.
- these CTC choices do not translate speech and do not stream partial text.
- optional post-processing can alter casing, punctuation, or number formatting, so compare raw output with post-processing disabled when evaluating the model itself.

## Privacy and model downloads

recording, VAD, GigaAM inference, history, and paste run on the local computer. GigaAM itself does not send audio to a transcription service. optional cloud post-processing is a separate feature and can send transcript text to the provider you configure.

model weights download separately from pinned Hugging Face repositories. GigaType verifies every declared bundle file by expected size and SHA256 before materializing it:

- `istupakov/gigaam-multilingual-ctc-onnx` at revision `458860e1983aef670dd9795fb6af603c82767d5d` for both 220M choices
- `istupakov/gigaam-multilingual-large-ctc-onnx` at revision `07665ab5e54371dd1ac7b8b10f06478003723573` for both 600M choices

after a model is downloaded and verified, transcription can run without network access. deleting GigaType's app-data model directory requires downloading the files again; use the app's About/debug view to locate the exact app-data directory.

## Verify SHA256

after publication, the authoritative hashes will be in the private release notes and will apply to the exact final asset names. for example:

```powershell
$asset = Join-Path $env:USERPROFILE "Downloads\GigaType_0.9.3-gigatype.1_x64-cuda13-setup.exe"
(Get-FileHash -LiteralPath $asset -Algorithm SHA256).Hash.ToLowerInvariant()
```

compare all 64 hexadecimal characters with the value beside the same filename in the private release notes. filename similarity, file size, or a hash from another release is insufficient. if the value differs, delete the file and download it again; do not use `Run anyway`.

to inspect several downloaded assets:

```powershell
Get-ChildItem (Join-Path $env:USERPROFILE "Downloads\GigaType_0.9.3-gigatype.1_x64*") -File |
  Get-FileHash -Algorithm SHA256 |
  Format-Table Path, Hash
```

## Troubleshooting

**Windows blocks the installer:** verify SHA256 first. when the hash matches the private release notes, use `More info -> Run anyway`; when it does not match, do not run the file.

**CUDA is unavailable:** run `& .\GigaType.exe --list-accelerators --json` from the installation directory. confirm you installed a `cuda13` asset and have a compatible NVIDIA driver. `Auto` may continue on CPU and report why; explicit `CUDA` returns an error. use the CPU package with `GigaAM Multilingual 220M INT8` if GPU acceleration is not required.

**model download fails:** confirm the machine can reach Hugging Face, then retry from the model selector. proxy/firewall failures are reported against the failing bundle file; GigaType does not silently substitute another model. partial staging is cleaned before a later retry.

**CPU transcription is too slow or memory-heavy:** select `GigaAM Multilingual 220M INT8`, close other memory-heavy applications, and avoid an FP32 CUDA-labeled model on CPU.

**output lacks capitals, punctuation, or digits:** this is expected raw GigaAM behavior. use optional post-processing only if its privacy and provider behavior are acceptable.

**a new private release is available:** GigaType does not use upstream Handy updates. download the new private asset and verify its release-specific SHA256 before installing it.

## Build from source

see [BUILD.md](BUILD.md) for exact prerequisites, clone commands, pinned runtime inputs, CPU/CUDA package gates, and output paths. source development remains cross-platform, but `0.9.3-gigatype.1` targets packaged releases only for Windows x64 when published.

## Repository layout

- `src/`: React/TypeScript settings, onboarding, model selection, and overlay UI
- `src-tauri/src/`: Rust application, audio pipeline, model catalog/bundles, transcription, shortcuts, and commands
- `src-tauri/resources/`: packaged VAD resources and third-party notices; GigaAM weights are deliberately absent
- `scripts/`: cross-platform helpers plus Windows CPU/CUDA build, audit, and verification entrypoints
- `tests/` and `src-tauri/tests/`: frontend contracts and Rust integration tests
- `.github/workflows/`: CI build and package-audit workflows
- `docs/superpowers/`: approved design and implementation-plan records for this fork

## License and upstream attribution

GigaType preserves Handy's Git history and source attribution. the source remains under the [MIT License](LICENSE), including `Copyright (c) 2025 CJ Pais`. GigaType is an unofficial private fork with independent branding and no upstream endorsement.

model weights are separate works and are not relicensed by this repository's MIT license. the multilingual ONNX exports come from [`istupakov/gigaam-multilingual-ctc-onnx`](https://huggingface.co/istupakov/gigaam-multilingual-ctc-onnx) and [`istupakov/gigaam-multilingual-large-ctc-onnx`](https://huggingface.co/istupakov/gigaam-multilingual-large-ctc-onnx), converted from [`ai-sage/GigaAM-Multilingual`](https://huggingface.co/ai-sage/GigaAM-Multilingual). review each model repository's model card and license before redistribution.

CPU packages include Microsoft ONNX Runtime's license and third-party notices. CUDA packages also include the official NVIDIA CUDA/cuDNN license files and [`THIRD_PARTY_NOTICES-CUDA.txt`](src-tauri/resources/licenses/THIRD_PARTY_NOTICES-CUDA.txt). those components remain under their respective licenses; NVIDIA driver libraries are supplied by the installed display driver and are not redistributed by GigaType.
