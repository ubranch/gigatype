$ErrorActionPreference = "Stop"

$entrypoint = Join-Path $PSScriptRoot "verify-windows-cuda.ps1"
if (-not (Test-Path -LiteralPath $entrypoint -PathType Leaf)) {
  throw "missing CUDA verification entrypoint: $entrypoint"
}

$source = Get-Content -LiteralPath $entrypoint -Raw
foreach ($required in @(
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
if ($source -notmatch 'Where-Object\s*\{\s*\$_.pid\s*-eq\s*\$ProcessId') {
  throw "VRAM evidence must filter nvidia-smi rows by exact Handy PID"
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

Write-Output "verify-windows-cuda plan contract: pass"
