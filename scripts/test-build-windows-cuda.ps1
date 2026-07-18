$ErrorActionPreference = "Stop"

$entrypoint = Join-Path $PSScriptRoot "build-windows-cuda.ps1"
if (-not (Test-Path -LiteralPath $entrypoint -PathType Leaf)) {
  throw "missing CUDA build entrypoint: $entrypoint"
}
$repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".."))
$appConfig = Get-Content -LiteralPath (Join-Path $repoRoot "src-tauri\tauri.conf.json") -Raw |
  ConvertFrom-Json
$productName = [string]$appConfig.productName
$version = [string]$appConfig.version
$executableName = "$productName.exe"
if (-not $productName -or -not $version) {
  throw "tauri.conf.json must define productName and version"
}
$commonResourceRoot = Join-Path $repoRoot "src-tauri\resources"
$commonCudaNotices = @(Get-ChildItem -LiteralPath $commonResourceRoot -Filter "THIRD_PARTY_NOTICES-CUDA.txt" -File -Recurse)
if ($commonCudaNotices.Count -gt 0) {
  throw "CUDA-only notice must live outside Tauri common resources: $($commonCudaNotices.FullName -join ', ')"
}
$cudaNoticeSource = Join-Path $repoRoot "src-tauri\cuda-resources\THIRD_PARTY_NOTICES-CUDA.txt"
if (-not (Test-Path -LiteralPath $cudaNoticeSource -PathType Leaf)) {
  throw "dedicated CUDA notice source is missing: $cudaNoticeSource"
}
$wixConfig = $appConfig.bundle.windows.PSObject.Properties["wix"]
if (-not $wixConfig -or [string]$wixConfig.Value.version -ne "0.9.3.2") {
  throw "tauri.conf.json must map release 0.9.3-gigatype.2 to MSI version 0.9.3.2"
}

$helperModule = Join-Path $PSScriptRoot "windows-package-helpers.ps1"
if (-not (Test-Path -LiteralPath $helperModule -PathType Leaf)) {
  throw "missing Windows package helper module: $helperModule"
}
. $helperModule

function Assert-ThrowsLike {
  param(
    [Parameter(Mandatory)][scriptblock]$Action,
    [Parameter(Mandatory)][string]$Pattern
  )

  $caught = $null
  try {
    & $Action
  } catch {
    $caught = $_
  }
  if ($null -eq $caught) {
    throw "expected action to throw: $Pattern"
  }
  if ($caught.Exception.Message -notlike $Pattern) {
    throw "unexpected error '$($caught.Exception.Message)'; expected $Pattern"
  }
}

$behaviorRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("gigatype-windows-helper-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $behaviorRoot | Out-Null
try {
  $missingArtifacts = Join-Path $behaviorRoot "missing"
  New-Item -ItemType Directory -Path $missingArtifacts | Out-Null
  Assert-ThrowsLike {
    Get-SingleVersionedArtifact -Directory $missingArtifacts -Version "0.9.3" -Extension ".exe" -Label "NSIS"
  } "*exactly one current-version artifact*"

  $wrongArtifacts = Join-Path $behaviorRoot "wrong-version"
  New-Item -ItemType Directory -Path $wrongArtifacts | Out-Null
  New-Item -ItemType File -Path (Join-Path $wrongArtifacts "$($productName)_0.9.30_x64-setup.exe") | Out-Null
  Assert-ThrowsLike {
    Get-SingleVersionedArtifact -Directory $wrongArtifacts -Version "0.9.3" -Extension ".exe" -Label "NSIS"
  } "*exactly one current-version artifact*"

  $staleArtifacts = Join-Path $behaviorRoot "stale"
  New-Item -ItemType Directory -Path $staleArtifacts | Out-Null
  New-Item -ItemType File -Path (Join-Path $staleArtifacts "$($productName)_0.9.3_x64-setup.exe") | Out-Null
  New-Item -ItemType File -Path (Join-Path $staleArtifacts "$($productName)_0.9.2_x64-setup.exe") | Out-Null
  Assert-ThrowsLike {
    Get-SingleVersionedArtifact -Directory $staleArtifacts -Version "0.9.3" -Extension ".exe" -Label "NSIS"
  } "*exactly one current-version artifact*"

  $duplicateArtifacts = Join-Path $behaviorRoot "duplicate"
  New-Item -ItemType Directory -Path $duplicateArtifacts | Out-Null
  New-Item -ItemType File -Path (Join-Path $duplicateArtifacts "$($productName)_0.9.3_x64-setup.exe") | Out-Null
  New-Item -ItemType File -Path (Join-Path $duplicateArtifacts "$($productName)_0.9.3_x64-portable.exe") | Out-Null
  Assert-ThrowsLike {
    Get-SingleVersionedArtifact -Directory $duplicateArtifacts -Version "0.9.3" -Extension ".exe" -Label "NSIS"
  } "*exactly one current-version artifact*"

  $validArtifacts = Join-Path $behaviorRoot "valid"
  New-Item -ItemType Directory -Path $validArtifacts | Out-Null
  $validName = "$($productName)_0.9.3_x64-setup.exe"
  New-Item -ItemType File -Path (Join-Path $validArtifacts $validName) | Out-Null
  $artifact = Get-SingleVersionedArtifact -Directory $validArtifacts -Version "0.9.3" -Extension ".exe" -Label "NSIS"
  if ($artifact.Name -ne $validName) { throw "valid current-version artifact was not returned" }

  $validMsiArtifacts = Join-Path $behaviorRoot "valid-msi"
  New-Item -ItemType Directory -Path $validMsiArtifacts | Out-Null
  $validMsiName = "$($productName)_0.9.3_x64_en-US.msi"
  New-Item -ItemType File -Path (Join-Path $validMsiArtifacts $validMsiName) | Out-Null
  $msiArtifact = Get-SingleVersionedArtifact -Directory $validMsiArtifacts -Version "0.9.3" -Extension ".msi" -Label "MSI"
  if ($msiArtifact.Name -ne $validMsiName) { throw "valid current-version MSI artifact was not returned" }

  $targetRoot = Join-Path $behaviorRoot "cargo-target-cpu"
  $bundleRoot = Join-Path $targetRoot "release\bundle"
  New-Item -ItemType Directory -Path $bundleRoot -Force | Out-Null
  New-Item -ItemType File -Path (Join-Path $targetRoot "compiled-cache.obj") | Out-Null
  New-Item -ItemType File -Path (Join-Path $bundleRoot "stale-installer.exe") | Out-Null
  Reset-OwnedDirectory -Path $bundleRoot -OwnedRoot $behaviorRoot
  if (-not (Test-Path -LiteralPath (Join-Path $targetRoot "compiled-cache.obj") -PathType Leaf)) {
    throw "owned bundle cleanup removed reusable parent target content"
  }
  if (@(Get-ChildItem -LiteralPath $bundleRoot -Force).Count -ne 0) {
    throw "owned bundle cleanup left stale bundle content"
  }

  $allowedModels = Join-Path $behaviorRoot "allowed-model-lower"
  New-Item -ItemType Directory -Path $allowedModels | Out-Null
  New-Item -ItemType File -Path (Join-Path $allowedModels "silero_vad_v4.onnx") | Out-Null
  if (@(Get-UnexpectedModelWeightFiles -Root $allowedModels).Count -ne 0) {
    throw "exact Silero runtime model identity must be allowed"
  }

  $allowedCaseVariant = Join-Path $behaviorRoot "allowed-model-upper"
  New-Item -ItemType Directory -Path $allowedCaseVariant | Out-Null
  # Windows package identity is case-insensitive, so this exact case variant is the same allowed runtime model.
  New-Item -ItemType File -Path (Join-Path $allowedCaseVariant "SILERO_VAD_V4.ONNX") | Out-Null
  if (@(Get-UnexpectedModelWeightFiles -Root $allowedCaseVariant).Count -ne 0) {
    throw "exact Silero runtime model identity must be allowed case-insensitively"
  }

  $lookalikeModels = Join-Path $behaviorRoot "lookalike-models"
  New-Item -ItemType Directory -Path $lookalikeModels | Out-Null
  foreach ($name in @(
    "silero_vad_v4.onnx.data",
    "prefix-silero_vad_v4.onnx",
    "silero_vad_v4-suffix.onnx"
  )) {
    New-Item -ItemType File -Path (Join-Path $lookalikeModels $name) | Out-Null
  }
  $lookalikes = @(Get-UnexpectedModelWeightFiles -Root $lookalikeModels)
  if ($lookalikes.Count -ne 3) {
    throw "Silero prefix, suffix, and external-data lookalikes must all be rejected"
  }
} finally {
  $tempRoot = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
  $resolvedBehaviorRoot = [System.IO.Path]::GetFullPath($behaviorRoot)
  if (-not $resolvedBehaviorRoot.StartsWith($tempRoot, [System.StringComparison]::OrdinalIgnoreCase) -or
    (Split-Path -Leaf $resolvedBehaviorRoot) -notlike "gigatype-windows-helper-*") {
    throw "refusing to remove unexpected helper-test path: $resolvedBehaviorRoot"
  }
  Remove-Item -LiteralPath $resolvedBehaviorRoot -Recurse -Force
}

$entrypointSource = Get-Content -LiteralPath $entrypoint -Raw
if ([regex]::Matches($entrypointSource, 'src-tauri\\tauri\.conf\.json').Count -ne 1) {
  throw "CUDA build entrypoint must read tauri.conf.json exactly once"
}
foreach ($requiredMetadataContract in @(
  '$productName = [string]$appConfig.productName',
  '$version = [string]$appConfig.version',
  '$executableName = "$productName.exe"',
  'Filter $executableName',
  'executable = $executable.FullName',
  '"$($productName)_${version}_x64-setup.exe"',
  '"$($productName)_${version}_x64_en-US.msi"',
  '"$($productName)_${version}_x64-cuda13-setup.exe"',
  '"$($productName)_${version}_x64-cuda13_en-US.msi"'
)) {
  if (-not $entrypointSource.Contains($requiredMetadataContract)) {
    throw "CUDA build entrypoint is missing product metadata contract: $requiredMetadataContract"
  }
}
if ($entrypointSource -match 'Filter\s+"handy\.exe"' -or
    $entrypointSource -match '"Handy_\$\{version\}') {
  throw "CUDA build entrypoint must not hardcode Handy package identity"
}
if ($entrypointSource -notmatch 'gigatype-cuda-build' -or
    $entrypointSource -notmatch 'gigatype-audit-') {
  throw "CUDA build entrypoint must use GigaType cache and audit prefixes"
}
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
if ($entrypointSource -notmatch 'cuda_cudart-LICENSE\.txt') {
  throw "CUDA package audit must require prepared runtime license files"
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
if ($entrypointSource -notmatch 'function Prepare-CpuRuntime') {
  throw "CPU edition must have a CPU-only ORT preparation path"
}
if ($entrypointSource -notmatch '\$prepared\s*=\s*if\s*\(\$Edition\s*-eq\s*"Cuda"\)\s*\{\s*Prepare-CudaRuntime\s*\}\s*else\s*\{\s*Prepare-CpuRuntime\s*\}') {
  throw "runtime preparation must dispatch by edition"
}
function Assert-ModelWeightRejected {
  param(
    [Parameter(Mandatory)][ValidateSet("Cuda", "Cpu")][string]$Edition,
    [Parameter(Mandatory)][string]$FileName
  )

  $tempBase = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
  $root = Join-Path $tempBase ("gigatype-package-audit-" + [guid]::NewGuid().ToString("N"))
  New-Item -ItemType Directory -Path $root | Out-Null
  try {
    New-Item -ItemType File -Path (Join-Path $root $executableName) | Out-Null
    New-Item -ItemType File -Path (Join-Path $root $FileName) | Out-Null
    try {
      $null = & $entrypoint -Mode Audit -Edition $Edition -PackageRoot $root -Json
      throw "$Edition package audit accepted model weight $FileName"
    } catch {
      if ($_.Exception.Message -notmatch 'package unexpectedly contains model weights') {
        throw "$Edition package audit did not reject $FileName as model weights: $($_.Exception.Message)"
      }
    }
  } finally {
    $resolvedRoot = [System.IO.Path]::GetFullPath($root)
    if (-not $resolvedRoot.StartsWith($tempBase, [System.StringComparison]::OrdinalIgnoreCase) -or
      (Split-Path -Leaf $resolvedRoot) -notlike "gigatype-package-audit-*") {
      throw "refusing to remove unexpected package-audit test path: $resolvedRoot"
    }
    Remove-Item -LiteralPath $resolvedRoot -Recurse -Force
  }
}

function Assert-CpuOrtLicenseRequired {
  param([Parameter(Mandatory)][string]$MissingName)

  $tempBase = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
  $root = Join-Path $tempBase ("gigatype-package-license-" + [guid]::NewGuid().ToString("N"))
  New-Item -ItemType Directory -Path $root | Out-Null
  try {
    New-Item -ItemType File -Path (Join-Path $root $executableName) | Out-Null
    foreach ($name in @("onnxruntime-LICENSE.txt", "onnxruntime-ThirdPartyNotices.txt")) {
      if ($name -ne $MissingName) {
        New-Item -ItemType File -Path (Join-Path $root $name) | Out-Null
      }
    }
    try {
      $null = & $entrypoint -Mode Audit -Edition Cpu -PackageRoot $root -Json
      throw "CPU package audit accepted missing ORT license $MissingName"
    } catch {
      if ($_.Exception.Message -notlike "*missing*$MissingName*") {
        throw "CPU package audit did not require $MissingName`: $($_.Exception.Message)"
      }
    }
  } finally {
    $resolvedRoot = [System.IO.Path]::GetFullPath($root)
    if (-not $resolvedRoot.StartsWith($tempBase, [System.StringComparison]::OrdinalIgnoreCase) -or
      (Split-Path -Leaf $resolvedRoot) -notlike "gigatype-package-license-*") {
      throw "refusing to remove unexpected package-license test path: $resolvedRoot"
    }
    Remove-Item -LiteralPath $resolvedRoot -Recurse -Force
  }
}

function Assert-CpuPackageRejected {
  param(
    [string[]]$ExpectedStagedDlls = @(),
    [string[]]$PackagedDlls = @(),
    [string[]]$PackageFiles = @(),
    [Parameter(Mandatory)][string]$Pattern
  )

  $tempBase = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
  $fixtureRoot = Join-Path $tempBase ("gigatype-cpu-package-behavior-" + [guid]::NewGuid().ToString("N"))
  $packageRoot = Join-Path $fixtureRoot "package"
  $stagedRoot = Join-Path $fixtureRoot "expected-staging"
  New-Item -ItemType Directory -Path $packageRoot, $stagedRoot | Out-Null
  try {
    foreach ($name in @(
      $executableName,
      "onnxruntime-LICENSE.txt",
      "onnxruntime-ThirdPartyNotices.txt"
    )) {
      New-Item -ItemType File -Path (Join-Path $packageRoot $name) | Out-Null
    }
    foreach ($name in $ExpectedStagedDlls) {
      New-Item -ItemType File -Path (Join-Path $stagedRoot $name) | Out-Null
    }
    foreach ($name in $PackagedDlls) {
      New-Item -ItemType File -Path (Join-Path $packageRoot $name) | Out-Null
    }
    foreach ($name in $PackageFiles) {
      New-Item -ItemType File -Path (Join-Path $packageRoot $name) | Out-Null
    }

    try {
      $null = & $entrypoint -Mode Audit -Edition Cpu -PackageRoot $packageRoot `
        -ExpectedStagedRuntimeDir $stagedRoot -Json
      throw "CPU package audit unexpectedly passed; expected $Pattern"
    } catch {
      if ($_.Exception.Message -notlike $Pattern) {
        throw "CPU package audit error '$($_.Exception.Message)' did not match $Pattern"
      }
    }
  } finally {
    $resolvedFixtureRoot = [System.IO.Path]::GetFullPath($fixtureRoot)
    if (-not $resolvedFixtureRoot.StartsWith($tempBase, [System.StringComparison]::OrdinalIgnoreCase) -or
      (Split-Path -Leaf $resolvedFixtureRoot) -notlike "gigatype-cpu-package-behavior-*") {
      throw "refusing to remove unexpected CPU package fixture path: $resolvedFixtureRoot"
    }
    Remove-Item -LiteralPath $resolvedFixtureRoot -Recurse -Force
  }
}

Assert-ModelWeightRejected -Edition Cpu -FileName "legacy-model.bin"
Assert-ModelWeightRejected -Edition Cpu -FileName "legacy-model.ggml"
Assert-ModelWeightRejected -Edition Cpu -FileName "current-model.onnx.data"
Assert-ModelWeightRejected -Edition Cuda -FileName "current-model.gguf"
Assert-ModelWeightRejected -Edition Cuda -FileName "current-model.onnx"
Assert-ModelWeightRejected -Edition Cuda -FileName "current-model.onnx.data"
Assert-CpuOrtLicenseRequired -MissingName "onnxruntime-LICENSE.txt"
Assert-CpuOrtLicenseRequired -MissingName "onnxruntime-ThirdPartyNotices.txt"
Assert-CpuPackageRejected `
  -ExpectedStagedDlls @("transcribe-core.dll", "ggml-runtime.dll") `
  -PackagedDlls @("transcribe-core.dll") `
  -Pattern "*package is missing staged runtime DLL ggml-runtime.dll*"
Assert-CpuPackageRejected `
  -PackageFiles @("THIRD_PARTY_NOTICES-CUDA.txt") `
  -Pattern "*CPU package unexpectedly contains NVIDIA metadata*THIRD_PARTY_NOTICES-CUDA.txt*"
foreach ($nvidiaLicense in @(
  "cuda_cudart-LICENSE.txt",
  "libcublas-LICENSE.txt",
  "libcufft-LICENSE.txt",
  "libnvjitlink-LICENSE.txt",
  "cudnn-LICENSE.txt"
)) {
  Assert-CpuPackageRejected `
    -PackageFiles @($nvidiaLicense) `
    -Pattern "*CPU package unexpectedly contains NVIDIA metadata*$nvidiaLicense*"
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
if ($plan.product_name -ne $productName -or $plan.version -ne $version -or
    $plan.executable -ne $executableName) {
  throw "CUDA build plan does not expose tauri product metadata"
}
if ($plan.artifacts.nsis -ne "GigaType_0.9.3-gigatype.2_x64-cuda13-setup.exe" -or
    $plan.artifacts.msi -ne "GigaType_0.9.3-gigatype.2_x64-cuda13_en-US.msi") {
  throw "unexpected CUDA release artifact names"
}
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
if ($cpuPlan.artifacts.nsis -ne "GigaType_0.9.3-gigatype.2_x64-setup.exe" -or
    $cpuPlan.artifacts.msi -ne "GigaType_0.9.3-gigatype.2_x64_en-US.msi") {
  throw "unexpected CPU release artifact names"
}
if ($cpuPlan.ort.asset -ne "onnxruntime-win-x64-1.24.2.zip") {
  throw "CPU edition must use the CPU-only ORT asset"
}
if ($cpuPlan.ort.sha256 -ne "8e3e9c826375352e29cb2614fe44f3d7a4b0ff7b8028ad7a456af9d949a7e8b0") {
  throw "unexpected CPU ORT SHA256"
}
if ($null -ne $cpuPlan.cuda -or $null -ne $cpuPlan.cudnn) {
  throw "CPU plan must not contain CUDA, cuDNN, or NVIDIA download metadata"
}

Write-Output "build-windows-cuda plan contract: pass"
