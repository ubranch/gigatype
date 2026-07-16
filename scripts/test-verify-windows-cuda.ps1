$ErrorActionPreference = "Stop"

$entrypoint = Join-Path $PSScriptRoot "verify-windows-cuda.ps1"
if (-not (Test-Path -LiteralPath $entrypoint -PathType Leaf)) {
  throw "missing CUDA verification entrypoint: $entrypoint"
}

$source = Get-Content -LiteralPath $entrypoint -Raw
foreach ($required in @(
  '$productName = [string]$appConfig.productName',
  '$version = [string]$appConfig.version',
  '$executableName = "$productName.exe"',
  'Filter $executableName',
  '$Package.executable',
  "CUDAExecutionProvider",
  "onnxruntime_providers_cuda.dll",
  "nvidia-smi",
  "--query-compute-apps=gpu_uuid,pid,used_gpu_memory",
  "--ort-accelerator",
  "--transcribe-file",
  "--repeat",
  "/PORTABLE",
  "msiexec.exe",
  "multilingual_large_ctc.onnx.data"
)) {
  if (-not $source.Contains($required)) {
    throw "CUDA verification entrypoint is missing contract token: $required"
  }
}
if ([regex]::Matches($source, 'src-tauri\\tauri\.conf\.json').Count -ne 1) {
  throw "CUDA verification entrypoint must read tauri.conf.json exactly once"
}
if ($source -match 'Filter\s+"handy\.exe"' -or
    $source -match '"Handy_\$\{version\}') {
  throw "CUDA verification entrypoint must not hardcode Handy package identity"
}
if ($source -notmatch 'gigatype-cuda-verify' -or
    $source -notmatch 'gigatype-cuda-build') {
  throw "CUDA verification entrypoint must use GigaType cache prefixes"
}
foreach ($expectedArtifact in @(
  '"$($productName)_${version}_x64-cuda13-setup.exe"',
  '"$($productName)_${version}_x64-cuda13_en-US.msi"'
)) {
  if (-not $source.Contains($expectedArtifact)) {
    throw "CUDA verification entrypoint is missing artifact contract: $expectedArtifact"
  }
}
if ($source -notmatch 'Where-Object\s*\{\s*\$_.pid\s*-eq\s*\$ProcessId') {
  throw "VRAM evidence must filter nvidia-smi rows by exact GigaType PID"
}
if ($source -notmatch 'ORT_LOG') {
  throw "CUDA verification must enable ORT provider logging"
}
if ($source -notmatch 'Remove-Item.+onnxruntime_providers_cuda\.dll') {
  throw "negative test must withhold only the provider DLL from a temporary package copy"
}

$planJson = & $entrypoint -Mode Plan -Json
if (-not $?) { throw "CUDA verification plan failed" }
$plan = $planJson | ConvertFrom-Json

if ($plan.product_name -ne "GigaType" -or
    $plan.version -ne "0.9.3-gigatype.1" -or
    $plan.executable -ne "GigaType.exe") {
  throw "verification plan does not expose tauri product metadata"
}
if ($plan.artifacts.nsis -ne "GigaType_0.9.3-gigatype.1_x64-cuda13-setup.exe" -or
    $plan.artifacts.msi -ne "GigaType_0.9.3-gigatype.1_x64-cuda13_en-US.msi") {
  throw "unexpected verification artifact names"
}
if ($plan.repeat -ne 3) { throw "verification requires exactly 3 measured runs by default" }
if ($plan.max_wer -ne 0.50) { throw "unexpected WER threshold" }
if ($plan.max_cuda_wer_regression -ne 0.02) { throw "unexpected CUDA WER regression threshold" }
if ($plan.fixture.dataset -ne "google/fleurs" -or $plan.fixture.config -ne "uz_uz" -or
    $plan.fixture.split -ne "validation" -or $plan.fixture.row -ne 72) {
  throw "unexpected deterministic FLEURS fixture selection"
}
if ($plan.fixture.pcm16_sha256 -ne "6825e20ded1faf4187e4d0330d502dd2fedb31869f18a5004eb89a07fa3b6238") {
  throw "unexpected normalized fixture SHA256"
}

$ids = @($plan.models | ForEach-Object id | Sort-Object)
$expectedIds = @(
  "gigaam-multilingual-220m-fp32-cuda",
  "gigaam-multilingual-600m-fp32-cuda"
)
if (Compare-Object $expectedIds $ids) { throw "unexpected verification model set" }
if (($plan.models | Where-Object id -eq "gigaam-multilingual-600m-fp32-cuda").files[1].local -ne
    "multilingual_large_ctc.onnx.data") {
  throw "large FP32 external-data local filename changed"
}
$smallModel = $plan.models | Where-Object id -eq "gigaam-multilingual-220m-fp32-cuda"
if ($smallModel.revision -ne "458860e1983aef670dd9795fb6af603c82767d5d" -or
    $smallModel.files[0].remote -ne "multilingual_ctc.onnx" -or
    $smallModel.files[1].remote -ne "multilingual_vocab.txt") {
  throw "small GigaAM model revision or asset names changed"
}
$largeModel = $plan.models | Where-Object id -eq "gigaam-multilingual-600m-fp32-cuda"
if ($largeModel.revision -ne "07665ab5e54371dd1ac7b8b10f06478003723573" -or
    $largeModel.files[0].remote -ne "multilingual_large_ctc.onnx" -or
    $largeModel.files[1].remote -ne "multilingual_large_ctc.onnx.data" -or
    $largeModel.files[2].remote -ne "multilingual_vocab.txt") {
  throw "large GigaAM model revision or asset names changed"
}

Write-Output "verify-windows-cuda plan contract: pass"
