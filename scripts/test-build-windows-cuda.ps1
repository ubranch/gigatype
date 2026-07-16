$ErrorActionPreference = "Stop"

$entrypoint = Join-Path $PSScriptRoot "build-windows-cuda.ps1"
if (-not (Test-Path -LiteralPath $entrypoint -PathType Leaf)) {
  throw "missing CUDA build entrypoint: $entrypoint"
}

$entrypointSource = Get-Content -LiteralPath $entrypoint -Raw
if ($entrypointSource -match '\$LASTEXITCODE') {
  throw "CUDA build entrypoint must use explicit Process.ExitCode; LASTEXITCODE is unset in WSL-launched PowerShell 7.6"
}
if ($entrypointSource -notmatch '\$bunDir\s*=\s*Split-Path -Parent \$bun') {
  throw "CUDA build entrypoint must resolve the Bun directory for Tauri beforeBuildCommand"
}
if ($entrypointSource -notmatch 'PATH=.*\$bunDir;') {
  throw "CUDA build entrypoint must prepend the Bun directory to PATH"
}
if ($entrypointSource -notmatch 'beforeBuildCommand\s*=\s*\$null') {
  throw "CUDA build entrypoint must disable Tauri beforeBuildCommand in its generated config"
}
if ($entrypointSource -notmatch '\$bun.*run build') {
  throw "CUDA build entrypoint must run the frontend build through the resolved Bun executable"
}
if ($entrypointSource -notmatch '@tauri-apps\\cli\\tauri\.js') {
  throw "CUDA build entrypoint must invoke Tauri's JS entrypoint directly"
}
if ($entrypointSource -match '\$bun.*run tauri') {
  throw "CUDA build entrypoint must not use Bun package-script environment for native compilation"
}
if ($entrypointSource -notmatch 'Join-Path \$CacheRoot "cargo\.cmd"') {
  throw "CUDA build entrypoint must name its environment-preserving wrapper cargo.cmd for Tauri PATH discovery"
}
if ($entrypointSource -notmatch 'set `"CARGO=\$cargoWrapper`"') {
  throw "CUDA build entrypoint must pin Tauri to the Cargo wrapper"
}
$vcvarsCallCount = [regex]::Matches($entrypointSource, 'call `"\$vcvars`" >nul').Count
if ($vcvarsCallCount -lt 2) {
  throw "Cargo wrapper must restore vcvars64.bat immediately before Cargo"
}
if ($entrypointSource -notmatch 'CARGO_ENCODED_RUSTFLAGS') {
  throw "CUDA build entrypoint must pass verified Windows SDK link directories directly to rustc"
}
if ($entrypointSource -notmatch 'set `"CL=\$compilerFlags`"') {
  throw "CUDA build entrypoint must pass verified Windows SDK includes through MSVC CL"
}
if ($entrypointSource -notmatch 'CC_SHELL_ESCAPED_FLAGS=1') {
  throw "CUDA build entrypoint must preserve quoted include paths containing spaces"
}
if ($entrypointSource -notmatch 'silero_vad_v4\.onnx') {
  throw "CUDA package audit must allow only the required bundled Silero VAD ONNX model"
}
if ($entrypointSource -notmatch 'cuda_cudart-LICENSE\.txt') {
  throw "CUDA package audit must require prepared runtime license files"
}
if ($entrypointSource -notmatch 'staged CUDA runtime DLL') {
  throw "CUDA package audit must require every staged runtime DLL"
}
if ($entrypointSource -notmatch '"bcryptprimitives\.dll"') {
  throw "package audit must permit the Windows bcrypt primitives system DLL"
}
if ($entrypointSource -notmatch '"vulkan-1\.dll"') {
  throw "package audit must permit the host Vulkan loader used by ggml-vulkan"
}
if ($entrypointSource -notmatch 'function Remove-AuditDirectoryWithRetry') {
  throw "package audit must retry transient Windows cleanup locks"
}
if ($entrypointSource -notmatch 'Remove-AuditDirectoryWithRetry \$root') {
  throw "package audit finally block must use bounded cleanup retry"
}

$verifier = Join-Path $PSScriptRoot "verify-windows-cuda.ps1"
$verifierSource = Get-Content -LiteralPath $verifier -Raw
if ($verifierSource -notmatch 'row = 72') {
  throw "CUDA verification must pin the natural long-form FLEURS row"
}
if ($verifierSource -notmatch '13\.56') {
  throw "CUDA fixture must remain within the large-model sequence window"
}
if ($verifierSource -match 'stream_loop') {
  throw "CUDA verification must not synthesize repeated CTC input"
}

$planJson = & $entrypoint -Mode Plan -Json
if ($LASTEXITCODE -ne 0) {
  throw "CUDA build plan exited $LASTEXITCODE"
}
$plan = $planJson | ConvertFrom-Json

if ($plan.edition -ne "cuda13") { throw "unexpected edition: $($plan.edition)" }
if ($plan.ort.version -ne "1.24.2") { throw "unexpected ORT version" }
if ($plan.ort.asset -ne "onnxruntime-win-x64-gpu_cuda13-1.24.2.zip") {
  throw "unexpected ORT asset"
}
if ($plan.ort.sha256 -ne "72207a283ec9886e1968a4183636a7665c78e2154d4f4adc16e61193dd7a74f1") {
  throw "unexpected ORT SHA256"
}
if ($plan.cuda.manifest -ne "redistrib_13.0.2.json") {
  throw "unexpected CUDA manifest"
}
if ($plan.cuda.manifest_sha256 -ne "fce66717a81c510ffeb89ecc3e79849ab34af3b80139f750876d9033e31d71c2") {
  throw "unexpected CUDA manifest SHA256"
}
if ($plan.cudnn.version -ne "9.16.0.29") { throw "unexpected cuDNN version" }
if ($plan.cudnn.sha256 -ne "606c405a46e55bec01be8dd81092d238900f4028fee10a7ed1bc32cd5e23714e") {
  throw "unexpected cuDNN SHA256"
}

$expectedComponents = @(
  "cuda_cudart",
  "cuda_nvrtc",
  "libcublas",
  "libcufft",
  "libnvjitlink"
)
$actualComponents = @($plan.cuda.components | Sort-Object)
if (Compare-Object $expectedComponents $actualComponents) {
  throw "unexpected CUDA runtime component set: $($actualComponents -join ', ')"
}

$cpuPlanJson = & $entrypoint -Mode Plan -Edition Cpu -Json
if ($LASTEXITCODE -ne 0) {
  throw "CPU build plan exited $LASTEXITCODE"
}
$cpuPlan = $cpuPlanJson | ConvertFrom-Json
if ($cpuPlan.edition -ne "cpu") { throw "unexpected CPU edition: $($cpuPlan.edition)" }

Write-Output "build-windows-cuda plan contract: pass"
