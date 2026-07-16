# Building GigaType

this guide covers source development on Windows, macOS, and Linux, plus the release-gated Windows x64 CPU and NVIDIA CUDA 13 packages for version `0.9.3-gigatype.1`.

Windows x64 is the only packaged release target. macOS and Linux remain supported source-development targets, but this release does not claim rebuilt or verified packages for them.

## Clone and version

```powershell
git clone https://github.com/ubranch/GigaType.git
cd GigaType
```

the package, Cargo, and Tauri versions must all remain `0.9.3-gigatype.1`. `src-tauri/tauri.conf.json` is the package scripts' source of truth for `productName`, version, executable name, and artifact names.

## Cross-platform prerequisites

all platforms need:

- [Git](https://git-scm.com/)
- current stable [Rust](https://rustup.rs/)
- [Bun](https://bun.sh/)
- the official [Tauri 2 prerequisites](https://tauri.app/start/prerequisites/)

install JavaScript dependencies once from the repository root:

```powershell
bun install
```

### Windows source prerequisites

- Windows x64 and PowerShell 7
- Visual Studio 2019/2022 or Visual Studio Build Tools with Desktop development with C++, the x64 MSVC toolchain, Windows SDK, and VC++ redistributable files
- [CMake](https://cmake.org/download/) on `PATH`
- [Vulkan SDK](https://vulkan.lunarg.com/sdk/home) with `VULKAN_SDK` available in a new terminal
- SPIR-V headers discoverable through `CMAKE_PREFIX_PATH`; the build script also recognizes `%LOCALAPPDATA%\handy-vcpkg\manifest\vcpkg_installed\x64-windows`

common installers:

```powershell
winget install Kitware.CMake
winget install KhronosGroup.VulkanSDK
```

the CUDA release verifier additionally requires `ffmpeg.exe`, `ffprobe.exe`, and `nvidia-smi.exe` on `PATH`. `nvidia-smi.exe` is supplied by the NVIDIA display driver. CUDA Toolkit developer tools are not required because the script stages pinned redistributable runtime archives.

### macOS source prerequisites

install Xcode Command Line Tools:

```bash
xcode-select --install
```

Intel macOS has no prebuilt ONNX Runtime input in this project. install ONNX Runtime with Homebrew and use dynamic linking:

```bash
brew install onnxruntime
ORT_LIB_LOCATION=$(brew --prefix onnxruntime)/lib ORT_PREFER_DYNAMIC_LINK=1 bun run tauri dev
ORT_LIB_LOCATION=$(brew --prefix onnxruntime)/lib ORT_PREFER_DYNAMIC_LINK=1 bun run tauri build
```

### Linux source prerequisites

install the Tauri, audio, Vulkan, and layer-shell development packages for the distribution:

```bash
# Ubuntu/Debian
sudo apt update
sudo apt install build-essential libasound2-dev pkg-config libssl-dev libvulkan-dev vulkan-tools glslc spirv-headers glslang-tools libgtk-3-dev libwebkit2gtk-4.1-dev libayatana-appindicator3-dev librsvg2-dev libgtk-layer-shell0 libgtk-layer-shell-dev patchelf cmake

# Fedora/RHEL
sudo dnf groupinstall "Development Tools"
sudo dnf install alsa-lib-devel pkgconf openssl-devel vulkan-devel \
  spirv-headers-devel spirv-tools-devel glslang glslc \
  gtk3-devel webkit2gtk4.1-devel libappindicator-gtk3-devel librsvg2-devel \
  gtk-layer-shell gtk-layer-shell-devel cmake

# Arch Linux
sudo pacman -S base-devel alsa-lib pkgconf openssl vulkan-devel \
  spirv-headers glslang shaderc gtk3 webkit2gtk-4.1 \
  libappindicator-gtk3 librsvg gtk-layer-shell cmake
```

## Source development

```powershell
bun run tauri dev
```

source checks used before packaging:

```powershell
bun test tests/model-source.test.ts tests/dropdown-accessibility.test.tsx tests/gigatype-branding.test.ts
bun run check:translations
bun run build
bun run lint
bun run format:check
cargo fmt --manifest-path src-tauri/Cargo.toml -- --check
cargo test --manifest-path src-tauri/Cargo.toml
cargo clippy --manifest-path src-tauri/Cargo.toml --all-targets -- -D warnings
```

`bun run tauri build` remains the generic current-platform source build. it does not by itself satisfy this fork's Windows release audit.

## Windows x64 release commands

run these from a PowerShell 7 prompt at `GigaType` repository root:

```powershell
bun install
& ./scripts/test-build-windows-cuda.ps1
& ./scripts/test-verify-windows-cuda.ps1
& ./scripts/build-windows-cuda.ps1 -Mode All -Edition Cpu
& ./scripts/verify-windows-cuda.ps1 -Mode All -Repeat 3
```

the two `test-*` commands are fast contract tests for parsing, pins, naming, path ownership, package-audit rules, and failure behavior. they do not compile or benchmark the application. the CPU `-Mode All` command prepares pinned CPU ONNX Runtime, builds both installers, audits both package formats, and launches packaged diagnostics. the CUDA verifier's `-Mode All` command prepares/builds/audits CUDA installers before running provider, transcript, timing, and VRAM gates.

inspect immutable inputs and names without downloading or building:

```powershell
& ./scripts/build-windows-cuda.ps1 -Mode Plan -Edition Cpu -Json
& ./scripts/build-windows-cuda.ps1 -Mode Plan -Edition Cuda -Json
& ./scripts/verify-windows-cuda.ps1 -Mode Plan -Json
```

`Plan` output is configuration evidence only. it is not package or runtime proof.

## Exact release outputs

a successful CPU build writes:

- `dist/windows-cpu/GigaType_0.9.3-gigatype.1_x64-setup.exe`
- `dist/windows-cpu/GigaType_0.9.3-gigatype.1_x64_en-US.msi`

a successful CUDA verification build writes:

- `dist/windows-cuda/GigaType_0.9.3-gigatype.1_x64-cuda13-setup.exe`
- `dist/windows-cuda/GigaType_0.9.3-gigatype.1_x64-cuda13_en-US.msi`

CUDA evidence is written under `dist/windows-cuda/verification/`, including artifact hashes, package audits, launch results, missing-provider proof, fixture metadata, benchmarks, and exact-PID VRAM evidence. `dist/`, installers, downloaded models, and caches are generated artifacts and must not be committed.

## Pinned package and model inputs

`scripts/build-windows-cuda.ps1` pins official inputs by immutable name/version and SHA256:

- CPU ONNX Runtime `onnxruntime-win-x64-1.24.2.zip`
- CUDA ONNX Runtime `onnxruntime-win-x64-gpu_cuda13-1.24.2.zip`
- NVIDIA CUDA redistributable manifest `redistrib_13.0.2.json`, with `cuda_cudart`, `cuda_nvrtc`, `libcublas`, `libcufft`, and `libnvjitlink`
- NVIDIA cuDNN `9.16.0.29` from `redistrib_9.16.0.json`

the GigaAM catalog and verifier pin model files by repository revision, byte count, and SHA256:

- `istupakov/gigaam-multilingual-ctc-onnx` at `458860e1983aef670dd9795fb6af603c82767d5d`
- `istupakov/gigaam-multilingual-large-ctc-onnx` at `07665ab5e54371dd1ac7b8b10f06478003723573`

model weights are downloaded separately and are rejected if size or SHA256 differs. no installer may contain model weight files.

## Caches and generated state

- `%LOCALAPPDATA%\gigatype-cuda-build` stores verified archives, extracted inputs, staged CPU/CUDA runtime trees, generated Tauri configs, command wrappers, and edition-specific Cargo target directories.
- `%LOCALAPPDATA%\gigatype-cuda-verify` stores the deterministic fixture, model blobs keyed by SHA256, temporary package work trees, process logs, and verification state.
- `dist/windows-cpu` and `dist/windows-cuda` contain final local packages; `dist/windows-cuda/verification` contains durable JSON evidence from the verifier.
- package-audit extraction uses uniquely named `%TEMP%\gigatype-audit-*` directories and removes only paths matching that owned prefix.

cache hits are accepted only after the script's expected size/SHA256 checks. deleting these caches forces downloads and rebuild work; it is not required for a normal repeat run.

## Package audit contract

both NSIS and MSI are extracted independently: NSIS uses silent portable extraction and MSI uses an administrative install. each extracted package must:

- contain `GigaType.exe` and all staged runtime DLLs
- contain no model weights
- contain ONNX Runtime license and third-party-notice files
- have zero unresolved non-system PE imports according to `dumpbin.exe`
- launch packaged `GigaType.exe --list-devices` successfully

CUDA packages must also contain the CUDA execution provider, required CUDA/cuDNN runtime DLLs, `THIRD_PARTY_NOTICES-CUDA.txt`, and each staged NVIDIA license. packaged `GigaType.exe --list-accelerators --json --ort-accelerator cuda` must succeed.

CPU packages must contain no CUDA provider/runtime DLL or NVIDIA CUDA/cuDNN notice/license metadata. this negative inventory gate is what keeps the CPU release small and provider-independent.

## CUDA negative-provider gate

the verifier creates an owned temporary hard-linked copy of an extracted CUDA package, deliberately withholds `onnxruntime_providers_cuda.dll`, and launches explicit CUDA diagnostics. acceptance requires non-zero exit plus a diagnostic naming the missing app-local provider. the test never mutates the original extracted package or installer.

## FLEURS, WER, timing, and VRAM proof

the CUDA verifier uses `google/fleurs`, config `uz_uz`, validation row `72`. it pins the source transcription and raw-audio SHA256, normalizes audio to a 13.56-second, 16 kHz, mono, 16-bit PCM WAV with `ffmpeg`, and verifies the decoded PCM SHA256. `-FixtureManifest` may reuse an existing matching `uz_uz` fixture, but it must pass the same reference and PCM checks.

for both `gigaam-multilingual-220m-fp32-cuda` and `gigaam-multilingual-600m-fp32-cuda`, the verifier runs the same packaged model/audio on CPU and CUDA at least three times. it requires:

- non-empty text and the explicitly requested ORT accelerator with no fallback
- reference WER at or below `0.50`
- CUDA WER regression versus CPU at or below `0.02`
- CUDA best transcription time below CPU best transcription time
- recorded load time, every transcription time, best time, audio duration, real-time factor, transcript, normalized text, WER, and provider log

for the 600M CUDA model, the verifier launches a dedicated measured process and samples GPU memory while that exact PID is alive. `nvidia-smi` establishes exact compute-process PID membership and records the matching row. accepted non-zero `used_memory_mb` is always derived from the Windows `\GPU Process Memory(*)\Dedicated Usage` counters for that PID. whether the `nvidia-smi` memory field is numeric or `N/A` changes only the recorded source label; its memory value is not accepted as the measurement. total GPU utilization or another process is not proof.

these gates prove the specific locally built artifacts, machine, driver, and pinned fixture used by the command. they do not establish a universal performance number or prove a separately uploaded release asset.

## Release SHA256

compute hashes only after every package gate passes and no further rebuild is planned:

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
  [pscustomobject]@{
    Name = $file.Name
    Bytes = $file.Length
    SHA256 = $hash.Hash.ToLowerInvariant()
  }
} | Format-Table -AutoSize
```

publish these final hashes beside the exact filenames in the private release notes. rebuilding any asset invalidates its previous hash and all upload comparisons.

## License staging

the source is MIT-licensed under the preserved root `LICENSE`. model weights remain under the terms published by their model repositories and are not part of source or installers. CPU packages stage ONNX Runtime `LICENSE` and `ThirdPartyNotices.txt`; CUDA packages additionally stage official CUDA and cuDNN license files plus `src-tauri/resources/licenses/THIRD_PARTY_NOTICES-CUDA.txt`.
