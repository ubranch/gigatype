# gigatype

> private, unofficial fork of `cjpais/Handy`. gigatype preserves upstream mit attribution and adds gigaam multilingual plus verified windows cuda packaging. it is not endorsed by or affiliated with upstream handy.

gigatype is a local desktop speech-to-text application: press a shortcut, speak, and paste the transcription into the focused text field. version `0.9.3-gigatype.1` targets separate cpu and nvidia cuda 13 packages for windows x64.

## what this fork adds

- four pinned gigaam multilingual ctc choices covering `uz`, `kk`, `ky`, `ru`, and `en`
- windows x64 cpu and nvidia cuda 13 packaging, with package-content and execution-provider audits
- explicit `Auto`, `CPU`, and `CUDA` behavior for onnx runtime models
- independent gigatype application identity, with upstream source history and mit attribution preserved
- no upstream updater or signing identity; private installers are unsigned and updates are installed manually

speech recognition, vad, history, and text insertion run locally. installers do not contain gigaam weights; selecting a model downloads its pinned files separately.

## download: cpu or cuda

when release `0.9.3-gigatype.1` is published, it targets the four windows x64 assets below. no packaged release is planned for other platforms.

| edition | installer                                        | use it when                                                      |
| ------- | ------------------------------------------------ | ---------------------------------------------------------------- |
| cpu     | `GigaType_0.9.3-gigatype.1_x64-setup.exe`        | recommended for systems without a supported nvidia gpu           |
| cpu     | `GigaType_0.9.3-gigatype.1_x64_en-US.msi`        | same cpu application in msi format                               |
| cuda 13 | `GigaType_0.9.3-gigatype.1_x64-cuda13-setup.exe` | nvidia gpu package with app-local onnx runtime cuda 13 libraries |
| cuda 13 | `GigaType_0.9.3-gigatype.1_x64-cuda13_en-US.msi` | same cuda application in msi format                              |

choose one package format and one edition. the cpu edition is smaller and does not include cuda runtime libraries. the cuda edition requires a compatible nvidia display driver; cuda developer tools are not required.

when published, the four assets will be distributed with the private gigatype release. access requires permission to the private repository.

## install on windows

1. after the private release is published, download one installer and find its sha256 in the matching release notes.
2. verify the local file with the command in [verify sha256](#verify-sha256). stop if the values differ.
3. run the `.exe` setup or `.msi`; do not install both formats.
4. installers published by this private fork are unsigned, so windows may show an unknown-publisher or microsoft defender smartscreen warning. only after the sha256 matches, select `More info -> Run anyway` when that option is shown.
5. launch gigatype. on the windows onboarding microphone card, select `Open System Settings`. in `Settings -> Privacy & security -> Microphone`, enable `Microphone access` and `Let desktop apps access your microphone`, then return to gigatype. repeat this settings step until onboarding shows the permission as granted.

gigatype has no automatic updater. verify and install a newer private package manually when one is published.

## first transcription

1. open gigatype and complete the windows microphone onboarding described above.
2. during onboarding, click `Show all models` before choosing a gigaam entry; gigaam models are not shown among the recommended cards. after onboarding, open `Settings -> Models`, where available models are listed directly without a `Show all models` control.
3. download and select `GigaAM Multilingual 220M INT8` on cpu, or the matching gpu recommendation below. wait until the model is marked downloaded.
4. `Auto` is the default onnx runtime accelerator. to inspect or change it, open `Settings -> Advanced`, enable `Experimental Features`, then under `Experimental` use `ONNX Acceleration`. choose `CPU` or `CUDA` explicitly only when needed for the selected edition or diagnostics.
5. the default windows transcription shortcut is `Ctrl+Space`, with push-to-talk enabled. configure either setting if that workflow is not convenient.
6. focus a text field, hold the shortcut while speaking, then release it. if push-to-talk is disabled, press once to start and once to stop. gigatype transcribes locally and inserts the result into the focused application.

the first model selection needs network access because model weights are not embedded in the installer.

## gigaam model guide

| model                                | intended use                                                                        |                                 download size |
| ------------------------------------ | ----------------------------------------------------------------------------------- | --------------------------------------------: |
| `GigaAM Multilingual 220M INT8`      | recommended cpu model                                                               |                 about 214 mib plus vocabulary |
| `GigaAM Multilingual 220M FP32 CUDA` | recommended balanced gpu model                                                      |                 about 844 mib plus vocabulary |
| `GigaAM Multilingual 600M INT8`      | larger cpu model; use only when its extra memory and processing cost are acceptable |                 about 564 mib plus vocabulary |
| `GigaAM Multilingual 600M FP32 CUDA` | recommended rtx 5080 model                                                          | about 2.18 gib plus onnx graph and vocabulary |

all four are multilingual ctc models for `uz`, `kk`, `ky`, `ru`, and `en`. `220M INT8` is the default recommendation for cpu use; `220M FP32 CUDA` balances gpu download size and model capacity; `600M FP32 CUDA` is the rtx 5080 recommendation.

## rtx 5080 setup

1. install either cuda 13 asset, after verifying its sha256.
2. install a compatible current nvidia display driver. the gigatype package supplies onnx runtime, cuda 13.0 update 2 runtime components, and cudnn 9.16.0.29 beside the application; it does not supply the driver.
3. download and select `GigaAM Multilingual 600M FP32 CUDA`.
4. use `Auto` for normal operation. use explicit `CUDA` when you want startup/model-load failure instead of cpu fallback if cuda is unavailable.
5. inspect provider state from the gigatype installation directory when needed:

```powershell
& .\GigaType.exe --list-accelerators --json
```

the repository verifier can measure cuda timing and exact-process vram use, but this readme does not promise a fixed speed or vram figure for every driver, audio sample, or machine.

## accelerator behavior

gigaam and other onnx models use the onnx runtime (`ORT`) accelerator setting. whisper-family ggml/gguf models use the separate `transcribe-cpp` accelerator setting, so changing ort does not select a whisper backend.

- `Auto`: uses cuda only when this windows x64 build includes cuda support and the cuda execution provider registers successfully. otherwise it selects cpu and records the diagnostic reason.
- `CPU`: forces onnx inference onto cpu.
- `CUDA`: requires usable cuda support. missing app-local runtime files, provider registration failure, or an incompatible/missing nvidia driver causes a clear error; explicit cuda does not silently continue on cpu.

the cpu package is built without the cuda execution provider. the cuda package carries an audited app-local cuda dependency set. package verification checks that cpu installers contain no cuda runtime and cuda installers contain the required provider/runtime files.

## model limitations

- supported languages are `uz`, `kk`, `ky`, `ru`, and `en`; other languages are outside this model bundle's contract.
- output is lowercase with little or no punctuation.
- the vocabulary has no digit tokens, so do not expect numeric digits in raw gigaam output.
- these ctc choices do not translate speech and do not stream partial text.
- optional post-processing can alter casing, punctuation, or number formatting, so compare raw output with post-processing disabled when evaluating the model itself.

## privacy and model downloads

recording, vad, gigaam inference, history, and paste run on the local computer. gigaam itself does not send audio to a transcription service. optional cloud post-processing is a separate feature and can send transcript text to the provider you configure.

model weights download separately from pinned hugging face repositories. gigatype verifies every declared bundle file by expected size and sha256 before materializing it:

- `istupakov/gigaam-multilingual-ctc-onnx` at revision `458860e1983aef670dd9795fb6af603c82767d5d` for both 220m choices
- `istupakov/gigaam-multilingual-large-ctc-onnx` at revision `07665ab5e54371dd1ac7b8b10f06478003723573` for both 600m choices

after a model is downloaded and verified, transcription can run without network access. deleting gigatype's app-data model directory requires downloading the files again; use the app's about/debug view to locate the exact app-data directory.

## verify sha256

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

## troubleshooting

**windows blocks the installer:** verify sha256 first. when the hash matches the private release notes, use `More info -> Run anyway`; when it does not match, do not run the file.

**cuda is unavailable:** run `& .\GigaType.exe --list-accelerators --json` from the installation directory. confirm you installed a `cuda13` asset and have a compatible nvidia driver. `Auto` may continue on cpu and report why; explicit `CUDA` returns an error. use the cpu package with `GigaAM Multilingual 220M INT8` if gpu acceleration is not required.

**model download fails:** confirm the machine can reach hugging face, then retry from the model selector. proxy/firewall failures are reported against the failing bundle file; gigatype does not silently substitute another model. partial staging is cleaned before a later retry.

**cpu transcription is too slow or memory-heavy:** select `GigaAM Multilingual 220M INT8`, close other memory-heavy applications, and avoid an fp32 cuda-labeled model on cpu.

**output lacks capitals, punctuation, or digits:** this is expected raw gigaam behavior. use optional post-processing only if its privacy and provider behavior are acceptable.

**a new private release is available:** gigatype does not use upstream handy updates. download the new private asset and verify its release-specific sha256 before installing it.

## build from source

see [`BUILD.md`](BUILD.md) for exact prerequisites, clone commands, pinned runtime inputs, cpu/cuda package gates, and output paths. source development remains cross-platform, but `0.9.3-gigatype.1` targets packaged releases only for windows x64 when published.

## repository layout

- `src/`: react/typescript settings, onboarding, model selection, and overlay ui
- `src-tauri/src/`: rust application, audio pipeline, model catalog/bundles, transcription, shortcuts, and commands
- `src-tauri/resources/`: packaged vad resources and third-party notices; gigaam weights are deliberately absent
- `scripts/`: cross-platform helpers plus windows cpu/cuda build, audit, and verification entrypoints
- `tests/` and `src-tauri/tests/`: frontend contracts and rust integration tests
- `.github/workflows/`: ci build and package-audit workflows
- `docs/superpowers/`: approved design and implementation-plan records for this fork

## license and upstream attribution

gigatype preserves handy's git history and source attribution. the source remains under the [mit license](LICENSE), including `Copyright (c) 2025 CJ Pais`. gigatype is an unofficial private fork with independent branding and no upstream endorsement.

model weights are separate works and are not relicensed by this repository's mit license. the multilingual onnx exports come from [`istupakov/gigaam-multilingual-ctc-onnx`](https://huggingface.co/istupakov/gigaam-multilingual-ctc-onnx) and [`istupakov/gigaam-multilingual-large-ctc-onnx`](https://huggingface.co/istupakov/gigaam-multilingual-large-ctc-onnx), converted from [`ai-sage/GigaAM-Multilingual`](https://huggingface.co/ai-sage/GigaAM-Multilingual). review each model repository's model card and license before redistribution.

cpu packages include microsoft onnx runtime's license and third-party notices. cuda packages also include the official nvidia cuda/cudnn license files and [`THIRD_PARTY_NOTICES-CUDA.txt`](src-tauri/cuda-resources/THIRD_PARTY_NOTICES-CUDA.txt). those components remain under their respective licenses; nvidia driver libraries are supplied by the installed display driver and are not redistributed by gigatype.
