[CmdletBinding()]
param(
  [ValidateSet("Plan", "Verify", "All")]
  [string]$Mode = "All",
  [string]$CacheRoot = (Join-Path $env:LOCALAPPDATA "handy-cuda-verify"),
  [string]$BuildCacheRoot = (Join-Path $env:LOCALAPPDATA "handy-cuda-build"),
  [string]$EvidenceDir,
  [string]$Nsis,
  [string]$Msi,
  [string]$FixtureManifest,
  [ValidateRange(3, 20)]
  [int]$Repeat = 3,
  [switch]$Json
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".."))
$CacheRoot = [System.IO.Path]::GetFullPath($CacheRoot)
$BuildCacheRoot = [System.IO.Path]::GetFullPath($BuildCacheRoot)
if (-not $EvidenceDir) {
  $EvidenceDir = Join-Path $repoRoot "dist\windows-cuda\verification"
}
$EvidenceDir = [System.IO.Path]::GetFullPath($EvidenceDir)

$fixtureSpec = [ordered]@{
  dataset = "google/fleurs"
  config = "uz_uz"
  split = "validation"
  row = 72
  reference = "ayrim hayvonlar masalan fillar va jirafalar mashinalarga yaqin kelishga moyil hamda standart uskunalar yaxshi tomosha qilish imkonini beradi"
  raw_sha256 = "9e6da750c37461c989c6041b89656d9b0cfcd3395d2c69d629fc341dbba0ad7c"
  pcm16_sha256 = "6825e20ded1faf4187e4d0330d502dd2fedb31869f18a5004eb89a07fa3b6238"
}

$vocabFile = [ordered]@{
  remote = "multilingual_vocab.txt"
  local = "vocab.txt"
  bytes = 393L
  sha256 = "4d130287892e1099fedfb3f93c4b4cf8a263151158801680b28977d1be4133f4"
}
$models = @(
  [ordered]@{
    id = "gigaam-multilingual-220m-fp32-cuda"
    repo = "istupakov/gigaam-multilingual-ctc-onnx"
    revision = "458860e1983aef670dd9795fb6af603c82767d5d"
    files = @(
      [ordered]@{
        remote = "multilingual_ctc.onnx"
        local = "model.onnx"
        bytes = 885388622L
        sha256 = "8bc803289f9cb5147ee95451fd9bdba219b1ecf1ddcd59a3651177c103c9eeec"
      },
      $vocabFile
    )
  },
  [ordered]@{
    id = "gigaam-multilingual-600m-fp32-cuda"
    repo = "istupakov/gigaam-multilingual-large-ctc-onnx"
    revision = "07665ab5e54371dd1ac7b8b10f06478003723573"
    files = @(
      [ordered]@{
        remote = "multilingual_large_ctc.onnx"
        local = "model.onnx"
        bytes = 909828L
        sha256 = "4a2d22279e90648262e1259e82982f1f1f7e2c4957e187c2b68459458c92fd5f"
      },
      [ordered]@{
        remote = "multilingual_large_ctc.onnx.data"
        local = "multilingual_large_ctc.onnx.data"
        bytes = 2343837696L
        sha256 = "5a7bf60fd3883a707dda19862b58a9a30777bde3e439ff76b49580da1f18b1f1"
      },
      $vocabFile
    )
  }
)

$plan = [ordered]@{
  edition = "windows-x64-cuda13"
  repeat = $Repeat
  max_wer = 0.50
  max_cuda_wer_regression = 0.02
  fixture = $fixtureSpec
  models = $models
  package_types = @("nsis-portable", "msi-administrative")
  negative_test = "withhold onnxruntime_providers_cuda.dll from temporary hard-linked package copy"
}

if ($Mode -eq "Plan") {
  if ($Json) { $plan | ConvertTo-Json -Depth 12 } else { $plan }
  exit 0
}

function Get-Sha256 {
  param([Parameter(Mandatory)][string]$Path)
  return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Write-JsonFile {
  param(
    [Parameter(Mandatory)]$Value,
    [Parameter(Mandatory)][string]$Path
  )
  $Value | ConvertTo-Json -Depth 15 | Set-Content -LiteralPath $Path -Encoding utf8
}

function Assert-OwnedCachePath {
  param([Parameter(Mandatory)][string]$Path)
  $root = $CacheRoot.TrimEnd([System.IO.Path]::DirectorySeparatorChar) +
    [System.IO.Path]::DirectorySeparatorChar
  $full = [System.IO.Path]::GetFullPath($Path)
  if (-not $full.StartsWith($root, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "refusing to modify path outside verification cache: $full"
  }
}

function Reset-OwnedDirectory {
  param([Parameter(Mandatory)][string]$Path)
  Assert-OwnedCachePath $Path
  if (Test-Path -LiteralPath $Path) {
    Remove-Item -LiteralPath $Path -Recurse -Force
  }
  New-Item -ItemType Directory -Path $Path -Force | Out-Null
}

function ConvertTo-NativeArgument {
  param([Parameter(Mandatory)][AllowEmptyString()][string]$Value)
  if ($Value -notmatch '[\s"]') { return $Value }
  return '"' + $Value.Replace('"', '\"') + '"'
}

function Start-CapturedProcess {
  param(
    [Parameter(Mandatory)][string]$FilePath,
    [Parameter(Mandatory)][string[]]$Arguments,
    [Parameter(Mandatory)][string]$LogPrefix,
    [hashtable]$Environment = @{}
  )
  $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
  $startInfo.FileName = $FilePath
  $startInfo.Arguments = (($Arguments | ForEach-Object { ConvertTo-NativeArgument $_ }) -join " ")
  $startInfo.UseShellExecute = $false
  $startInfo.CreateNoWindow = $true
  $startInfo.RedirectStandardOutput = $true
  $startInfo.RedirectStandardError = $true
  foreach ($name in $Environment.Keys) {
    $startInfo.Environment[$name] = [string]$Environment[$name]
  }

  $process = [System.Diagnostics.Process]::new()
  $process.StartInfo = $startInfo
  if (-not $process.Start()) { throw "failed to start $FilePath" }
  return [pscustomobject]@{
    process = $process
    stdout_task = $process.StandardOutput.ReadToEndAsync()
    stderr_task = $process.StandardError.ReadToEndAsync()
    stdout_path = "$LogPrefix.stdout.log"
    stderr_path = "$LogPrefix.stderr.log"
    command = "$FilePath $($startInfo.Arguments)"
  }
}

function Complete-CapturedProcess {
  param(
    [Parameter(Mandatory)]$Run,
    [int]$TimeoutSeconds = 1800
  )
  if (-not $Run.process.WaitForExit($TimeoutSeconds * 1000)) {
    $Run.process.Kill($true)
    throw "process timed out after $TimeoutSeconds seconds: $($Run.command)"
  }
  $stdout = $Run.stdout_task.GetAwaiter().GetResult()
  $stderr = $Run.stderr_task.GetAwaiter().GetResult()
  Set-Content -LiteralPath $Run.stdout_path -Value $stdout -Encoding utf8 -NoNewline
  Set-Content -LiteralPath $Run.stderr_path -Value $stderr -Encoding utf8 -NoNewline
  return [pscustomobject]@{
    exit_code = $Run.process.ExitCode
    pid = $Run.process.Id
    stdout = $stdout.Trim()
    stderr = $stderr.Trim()
    stdout_path = $Run.stdout_path
    stderr_path = $Run.stderr_path
    command = $Run.command
  }
}

function Invoke-CapturedProcess {
  param(
    [Parameter(Mandatory)][string]$FilePath,
    [Parameter(Mandatory)][string[]]$Arguments,
    [Parameter(Mandatory)][string]$LogPrefix,
    [hashtable]$Environment = @{},
    [int]$TimeoutSeconds = 1800
  )
  $run = Start-CapturedProcess $FilePath $Arguments $LogPrefix $Environment
  return Complete-CapturedProcess $run $TimeoutSeconds
}

function Get-VerifiedDownload {
  param(
    [Parameter(Mandatory)][string]$Url,
    [Parameter(Mandatory)][string]$Path,
    [Parameter(Mandatory)][long]$Bytes,
    [Parameter(Mandatory)][string]$Sha256
  )
  Assert-OwnedCachePath $Path
  New-Item -ItemType Directory -Path (Split-Path -Parent $Path) -Force | Out-Null
  if ((Test-Path -LiteralPath $Path -PathType Leaf) -and
      (Get-Item -LiteralPath $Path).Length -eq $Bytes -and
      (Get-Sha256 $Path) -eq $Sha256) {
    Write-Host "verified cache hit: $(Split-Path -Leaf $Path)"
    return $Path
  }

  if (Test-Path -LiteralPath $Path) { Remove-Item -LiteralPath $Path -Force }
  $partial = "$Path.download"
  if (Test-Path -LiteralPath $partial) { Remove-Item -LiteralPath $partial -Force }
  Write-Host "download: $Url"
  $curl = Invoke-CapturedProcess "curl.exe" @(
    "--fail", "--location", "--retry", "3", "--output", $partial, $Url
  ) "$Path.curl" @{} 7200
  if ($curl.exit_code -ne 0) { throw "download failed for $Url`: $($curl.stderr)" }
  $actualBytes = (Get-Item -LiteralPath $partial).Length
  if ($actualBytes -ne $Bytes) {
    throw "download size mismatch for $Url`: expected $Bytes, got $actualBytes"
  }
  $actualSha256 = Get-Sha256 $partial
  if ($actualSha256 -ne $Sha256) {
    throw "download SHA256 mismatch for $Url`: expected $Sha256, got $actualSha256"
  }
  Move-Item -LiteralPath $partial -Destination $Path
  return $Path
}

function Assert-DeterministicPcmFixture {
  param([Parameter(Mandatory)][string]$Path)
  $fixtureCache = Join-Path $CacheRoot "fixtures"
  New-Item -ItemType Directory -Path $fixtureCache -Force | Out-Null
  $ffprobe = (Get-Command "ffprobe.exe" -ErrorAction Stop).Source
  $probe = Invoke-CapturedProcess $ffprobe @(
    "-v", "error", "-show_entries",
    "stream=codec_name,sample_rate,channels,bits_per_sample,duration",
    "-of", "json", $Path
  ) (Join-Path $fixtureCache "ffprobe-fixture") @{} 120
  if ($probe.exit_code -ne 0) { throw "fixture probe failed: $($probe.stderr)" }
  $stream = ($probe.stdout | ConvertFrom-Json).streams[0]
  if ($stream.codec_name -ne "pcm_s16le" -or [int]$stream.sample_rate -ne 16000 -or
      [int]$stream.channels -ne 1 -or [int]$stream.bits_per_sample -ne 16 -or
      [Math]::Abs([double]$stream.duration - 13.56) -gt 0.001) {
    throw "normalized fixture must be 13.56s 16 kHz mono 16-bit PCM WAV"
  }

  $decodedPath = Join-Path $fixtureCache "fleurs-uz_uz-validation-72-decoded.s16le"
  $ffmpeg = (Get-Command "ffmpeg.exe" -ErrorAction Stop).Source
  $decode = Invoke-CapturedProcess $ffmpeg @(
    "-v", "error", "-y", "-i", $Path, "-f", "s16le", "-acodec", "pcm_s16le", $decodedPath
  ) (Join-Path $fixtureCache "ffmpeg-decode-fixture") @{} 120
  if ($decode.exit_code -ne 0) { throw "fixture PCM decode failed: $($decode.stderr)" }
  if ((Get-Item -LiteralPath $decodedPath).Length -ne 433920L -or
      (Get-Sha256 $decodedPath) -ne $fixtureSpec.pcm16_sha256) {
    throw "normalized fixture decoded PCM mismatch"
  }
}

function Get-DeterministicFixture {
  param([string]$ManifestPath)
  if ($ManifestPath -and (Test-Path -LiteralPath $ManifestPath -PathType Leaf)) {
    $entries = @(Get-Content -LiteralPath $ManifestPath -Raw | ConvertFrom-Json)
    $entry = $entries | Where-Object { $_.language -eq "uz_uz" } | Select-Object -First 1
    if ($entry -and (Test-Path -LiteralPath $entry.wav_path -PathType Leaf)) {
      if ([string]$entry.reference -eq $fixtureSpec.reference) {
        Assert-DeterministicPcmFixture ([string]$entry.wav_path)
        return [pscustomobject]@{
          language = "uz_uz"
          wav_path = [System.IO.Path]::GetFullPath([string]$entry.wav_path)
          reference = $fixtureSpec.reference
          sha256 = Get-Sha256 ([string]$entry.wav_path)
          decoded_pcm_sha256 = $fixtureSpec.pcm16_sha256
          source = "existing manifest"
        }
      }
    }
  }

  $fixtureCache = Join-Path $CacheRoot "fixtures"
  New-Item -ItemType Directory -Path $fixtureCache -Force | Out-Null
  $rawPath = Join-Path $fixtureCache "fleurs-uz_uz-validation-72-f32.wav"
  $pcmPath = Join-Path $fixtureCache "fleurs-uz_uz-validation-72-pcm16.wav"
  $needsConversion = -not (Test-Path -LiteralPath $pcmPath -PathType Leaf)
  if (-not $needsConversion) {
    try { Assert-DeterministicPcmFixture $pcmPath } catch { $needsConversion = $true }
  }
  if ($needsConversion) {
    $endpoint = "https://datasets-server.huggingface.co/rows?dataset=google/fleurs&config=uz_uz&split=validation&offset=72&length=1"
    $rowPath = Join-Path $fixtureCache "fleurs-row-72.json"
    $query = Invoke-CapturedProcess "curl.exe" @(
      "--fail", "--location", "--retry", "3", "--output", $rowPath, $endpoint
    ) (Join-Path $fixtureCache "fleurs-row-query") @{} 300
    if ($query.exit_code -ne 0) { throw "FLEURS row query failed: $($query.stderr)" }
    $row = (Get-Content -LiteralPath $rowPath -Raw | ConvertFrom-Json).rows[0].row
    if ([string]$row.transcription -ne $fixtureSpec.reference) {
      throw "pinned FLEURS row transcription changed"
    }
    $audioUrl = [string]$row.audio[0].src
    $null = Get-VerifiedDownload $audioUrl $rawPath 867898L $fixtureSpec.raw_sha256
    $ffmpeg = (Get-Command "ffmpeg.exe" -ErrorAction Stop).Source
    $convert = Invoke-CapturedProcess $ffmpeg @(
      "-v", "error", "-y", "-i", $rawPath,
      "-ac", "1", "-ar", "16000", "-c:a", "pcm_s16le", $pcmPath
    ) (Join-Path $fixtureCache "ffmpeg-fixture") @{} 120
    if ($convert.exit_code -ne 0) { throw "fixture conversion failed: $($convert.stderr)" }
    Assert-DeterministicPcmFixture $pcmPath
  }

  return [pscustomobject]@{
    language = "uz_uz"
    wav_path = $pcmPath
    reference = $fixtureSpec.reference
    sha256 = Get-Sha256 $pcmPath
    decoded_pcm_sha256 = $fixtureSpec.pcm16_sha256
    source = "google/fleurs uz_uz validation row 72"
  }
}

function Expand-Packages {
  param(
    [Parameter(Mandatory)][string]$NsisPath,
    [Parameter(Mandatory)][string]$MsiPath,
    [Parameter(Mandatory)][string]$WorkRoot
  )
  Reset-OwnedDirectory $WorkRoot
  $nsisRoot = Join-Path $WorkRoot "nsis"
  $msiRoot = Join-Path $WorkRoot "msi"
  New-Item -ItemType Directory -Path $nsisRoot, $msiRoot -Force | Out-Null

  $nsisProcess = Start-Process -FilePath $NsisPath `
    -ArgumentList @("/S", "/PORTABLE", "/D=$nsisRoot") -Wait -PassThru
  if ($nsisProcess.ExitCode -ne 0) { throw "NSIS portable extraction exited $($nsisProcess.ExitCode)" }

  $msiLog = Join-Path $WorkRoot "msi-admin.log"
  $msiArguments = "/a `"$MsiPath`" /qn /L*v `"$msiLog`" TARGETDIR=`"$msiRoot`""
  $msiProcess = Start-Process -FilePath "msiexec.exe" -ArgumentList $msiArguments -Wait -PassThru
  if ($msiProcess.ExitCode -ne 0) { throw "MSI administrative extraction exited $($msiProcess.ExitCode)" }

  $packages = @()
  foreach ($item in @(@("nsis", $nsisRoot), @("msi", $msiRoot))) {
    $handy = Get-ChildItem -LiteralPath $item[1] -Filter "handy.exe" -File -Recurse |
      Select-Object -First 1
    if (-not $handy) { throw "$($item[0]) extraction is missing handy.exe" }
    Set-Content -LiteralPath (Join-Path $handy.DirectoryName "portable") `
      -Value "Handy Portable Mode" -Encoding ascii -NoNewline
    New-Item -ItemType Directory -Path (Join-Path $handy.DirectoryName "Data\models") -Force |
      Out-Null
    $packages += [pscustomobject]@{
      kind = $item[0]
      root = $item[1]
      exe_dir = $handy.DirectoryName
      handy = $handy.FullName
      data = Join-Path $handy.DirectoryName "Data"
    }
  }
  return $packages
}

function Get-PackageAudit {
  param(
    [Parameter(Mandatory)]$Package,
    [Parameter(Mandatory)][string]$BuildScript
  )
  $auditJson = & $BuildScript -Mode Audit -PackageRoot $Package.root -Edition Cuda -Json
  if (-not $?) { throw "$($Package.kind) package audit failed" }
  $audit = ($auditJson -join [Environment]::NewLine) | ConvertFrom-Json
  return $audit.audit
}

function Test-PackageLaunch {
  param(
    [Parameter(Mandatory)]$Package,
    [Parameter(Mandatory)][string]$LogRoot
  )
  $devices = Invoke-CapturedProcess $Package.handy @("--list-devices") `
    (Join-Path $LogRoot "$($Package.kind)-devices") @{} 120
  if ($devices.exit_code -ne 0) {
    throw "$($Package.kind) --list-devices exited $($devices.exit_code): $($devices.stderr)"
  }

  $diagnostics = Invoke-CapturedProcess $Package.handy @(
    "--list-accelerators", "--json", "--ort-accelerator", "cuda"
  ) (Join-Path $LogRoot "$($Package.kind)-cuda-diagnostics") `
    @{ RUST_LOG = "info"; ORT_LOG = "info" } 120
  if ($diagnostics.exit_code -ne 0) {
    throw "$($Package.kind) CUDA diagnostics exited $($diagnostics.exit_code): $($diagnostics.stderr)"
  }
  $parsed = $diagnostics.stdout | ConvertFrom-Json
  $cuda = $parsed.ort | Where-Object { $_.id -eq "cuda" } | Select-Object -First 1
  if (-not $cuda -or -not $cuda.compiled -or -not $cuda.usable -or
      $parsed.ort_selected -ne "cuda" -or $parsed.ort_fallback_reason) {
    throw "$($Package.kind) CUDA diagnostic did not prove strict usable CUDA selection"
  }
  if ($diagnostics.stderr -notmatch "CUDAExecutionProvider registration probe succeeded") {
    throw "$($Package.kind) log lacks successful CUDAExecutionProvider registration"
  }
  if ($diagnostics.stderr -match "(?i)(LoadLibrary|missing.+dll|registration probe unavailable)") {
    throw "$($Package.kind) CUDA diagnostic contains missing-runtime warning"
  }
  return [pscustomobject]@{
    kind = $Package.kind
    list_devices_exit = $devices.exit_code
    diagnostics_exit = $diagnostics.exit_code
    cuda_compiled = [bool]$cuda.compiled
    cuda_usable = [bool]$cuda.usable
    selected = [string]$parsed.ort_selected
    provider_log = "CUDAExecutionProvider registration probe succeeded"
    device_output = $devices.stdout
  }
}

function Copy-HardLinkedTree {
  param(
    [Parameter(Mandatory)][string]$Source,
    [Parameter(Mandatory)][string]$Destination
  )
  Reset-OwnedDirectory $Destination
  foreach ($directory in Get-ChildItem -LiteralPath $Source -Directory -Recurse) {
    $relative = [System.IO.Path]::GetRelativePath($Source, $directory.FullName)
    New-Item -ItemType Directory -Path (Join-Path $Destination $relative) -Force | Out-Null
  }
  foreach ($file in Get-ChildItem -LiteralPath $Source -File -Recurse) {
    $relative = [System.IO.Path]::GetRelativePath($Source, $file.FullName)
    $target = Join-Path $Destination $relative
    New-Item -ItemType Directory -Path (Split-Path -Parent $target) -Force | Out-Null
    try {
      New-Item -ItemType HardLink -Path $target -Target $file.FullName -ErrorAction Stop | Out-Null
    } catch {
      Copy-Item -LiteralPath $file.FullName -Destination $target
    }
  }
}

function Test-MissingProviderFailure {
  param(
    [Parameter(Mandatory)]$Package,
    [Parameter(Mandatory)][string]$NegativeRoot,
    [Parameter(Mandatory)][string]$LogRoot
  )
  Copy-HardLinkedTree $Package.root $NegativeRoot
  $negativeExe = Get-ChildItem -LiteralPath $NegativeRoot -Filter "handy.exe" -File -Recurse |
    Select-Object -First 1
  $negativeProvider = Get-ChildItem -LiteralPath $negativeRoot `
    -Filter "onnxruntime_providers_cuda.dll" -File -Recurse | Select-Object -First 1
  if (-not $negativeProvider) { throw "temporary negative package lacks CUDA provider before test" }
  Remove-Item -LiteralPath (Join-Path $negativeProvider.DirectoryName "onnxruntime_providers_cuda.dll") -Force

  $result = Invoke-CapturedProcess $negativeExe.FullName @(
    "--list-accelerators", "--json", "--ort-accelerator", "cuda"
  ) (Join-Path $LogRoot "missing-provider") @{ RUST_LOG = "info"; ORT_LOG = "info" } 120
  if ($result.exit_code -eq 0) { throw "explicit CUDA succeeded without provider DLL" }
  if ($result.stderr -notmatch "CUDAExecutionProvider registration failed") {
    throw "missing-provider failure lacks actionable registration error: $($result.stderr)"
  }
  return [pscustomobject]@{
    exit_code = $result.exit_code
    withheld = "onnxruntime_providers_cuda.dll"
    error = ($result.stderr -split "`r?`n" | Where-Object {
      $_ -match "CUDAExecutionProvider registration failed"
    } | Select-Object -First 1)
  }
}

function Get-ModelCachePath {
  param([Parameter(Mandatory)]$File)
  return Join-Path (Join-Path $CacheRoot "models") "$($File.sha256).blob"
}

function Get-ModelFiles {
  $resolved = @{}
  foreach ($model in $models) {
    $modelFiles = @()
    foreach ($file in $model.files) {
      $cachePath = Get-ModelCachePath $file
      $url = "https://huggingface.co/$($model.repo)/resolve/$($model.revision)/$($file.remote)"
      $modelFiles += Get-VerifiedDownload $url $cachePath $file.bytes $file.sha256
    }
    $resolved[$model.id] = $modelFiles
  }
  return $resolved
}

function Materialize-Models {
  param(
    [Parameter(Mandatory)]$Package,
    [Parameter(Mandatory)]$CachedFiles
  )
  $modelsRoot = Join-Path $Package.data "models"
  foreach ($model in $models) {
    $modelRoot = Join-Path $modelsRoot $model.id
    if (Test-Path -LiteralPath $modelRoot) { Remove-Item -LiteralPath $modelRoot -Recurse -Force }
    New-Item -ItemType Directory -Path $modelRoot -Force | Out-Null
    for ($index = 0; $index -lt $model.files.Count; $index++) {
      $source = $CachedFiles[$model.id][$index]
      $destination = Join-Path $modelRoot $model.files[$index].local
      try {
        New-Item -ItemType HardLink -Path $destination -Target $source -ErrorAction Stop | Out-Null
      } catch {
        Copy-Item -LiteralPath $source -Destination $destination
      }
      if ((Get-Item -LiteralPath $destination).Length -ne $model.files[$index].bytes) {
        throw "materialized model size mismatch: $destination"
      }
    }
  }
}

function Normalize-Transcript {
  param([Parameter(Mandatory)][string]$Text)
  $normalized = $Text.ToLowerInvariant()
  $normalized = $normalized.Replace([char]0x2019, "'").Replace([char]0x02BB, "'")
  $normalized = $normalized.Replace([char]0x02BC, "'").Replace('`', "'")
  $normalized = [regex]::Replace($normalized, "[^\p{L}'\s]", " ")
  return ([regex]::Replace($normalized, "\s+", " ")).Trim()
}

function Get-WordErrorRate {
  param(
    [Parameter(Mandatory)][string]$Reference,
    [Parameter(Mandatory)][string]$Hypothesis
  )
  $referenceWords = @($Reference -split " " | Where-Object { $_ })
  $hypothesisWords = @($Hypothesis -split " " | Where-Object { $_ })
  if ($referenceWords.Count -eq 0) { return [double]($hypothesisWords.Count -gt 0) }
  $previous = [int[]](0..$hypothesisWords.Count)
  for ($referenceIndex = 0; $referenceIndex -lt $referenceWords.Count; $referenceIndex++) {
    $current = [int[]]::new($hypothesisWords.Count + 1)
    $current[0] = $referenceIndex + 1
    for ($hypothesisIndex = 0; $hypothesisIndex -lt $hypothesisWords.Count; $hypothesisIndex++) {
      $cost = [int]($referenceWords[$referenceIndex] -ne $hypothesisWords[$hypothesisIndex])
      $substitution = $previous[$hypothesisIndex] + $cost
      $insertion = $current[$hypothesisIndex] + 1
      $deletion = $previous[$hypothesisIndex + 1] + 1
      $current[$hypothesisIndex + 1] = [Math]::Min($substitution, [Math]::Min($insertion, $deletion))
    }
    $previous = $current
  }
  return $previous[$hypothesisWords.Count] / [double]$referenceWords.Count
}

function Get-VramSample {
  param([Parameter(Mandatory)][int]$ProcessId)
  $nvidiaSmi = (Get-Command "nvidia-smi.exe" -ErrorAction Stop).Source
  $gpuQuery = Invoke-CapturedProcess $nvidiaSmi @(
    "--query-gpu=uuid,name", "--format=csv,noheader,nounits"
  ) (Join-Path $CacheRoot "nvidia-smi-gpu") @{} 30
  if ($gpuQuery.exit_code -ne 0) { return $null }
  $gpuRows = @($gpuQuery.stdout -split "`r?`n" | Where-Object { $_ })
  $gpuNames = @{}
  foreach ($line in $gpuRows) {
    $parts = $line -split ",\s*", 2
    if ($parts.Count -eq 2) { $gpuNames[$parts[0]] = $parts[1] }
  }
  $appQuery = Invoke-CapturedProcess $nvidiaSmi @(
    "--query-compute-apps=gpu_uuid,pid,used_gpu_memory",
    "--format=csv,noheader,nounits"
  ) (Join-Path $CacheRoot "nvidia-smi-exact-pid") @{} 30
  if ($appQuery.exit_code -ne 0) { return $null }
  $appLines = @($appQuery.stdout -split "`r?`n" | Where-Object { $_ })
  $rows = foreach ($line in $appLines) {
    $parts = $line -split ",\s*", 3
    if ($parts.Count -ge 3 -and $parts[1] -match "^\d+$" -and
        [int]$parts[1] -eq $ProcessId) {
      $counterSamples = @(Get-Counter "\GPU Process Memory(*)\Dedicated Usage" `
        -ErrorAction SilentlyContinue | Select-Object -ExpandProperty CounterSamples |
        Where-Object { $_.InstanceName -match "^pid_$($parts[1])_" })
      $dedicatedBytes = [long](($counterSamples | Measure-Object -Property CookedValue -Sum).Sum)
      [pscustomobject]@{
        gpu_uuid = $parts[0]
        pid = [int]$parts[1]
        used_memory_mb = [int][Math]::Ceiling($dedicatedBytes / 1MB)
        dedicated_bytes = $dedicatedBytes
        gpu_name = [string]$gpuNames[$parts[0]]
        nvidia_smi_used_memory = $parts[2]
        nvidia_smi_row = $line
        memory_source = if ($parts[2] -match "^\d+$") {
          "nvidia-smi"
        } else {
          "Windows GPU Process Memory/Dedicated Usage; nvidia-smi WDDM memory=N/A"
        }
      }
    }
  }
  return $rows | Where-Object { $_.pid -eq $ProcessId } |
    Sort-Object used_memory_mb -Descending | Select-Object -First 1
}

function Invoke-Benchmark {
  param(
    [Parameter(Mandatory)]$Package,
    [Parameter(Mandatory)]$Model,
    [Parameter(Mandatory)][ValidateSet("cpu", "cuda")][string]$Accelerator,
    [Parameter(Mandatory)]$Fixture,
    [Parameter(Mandatory)][string]$LogRoot,
    [switch]$MonitorVram
  )
  $prefix = Join-Path $LogRoot "$($Model.id)-$Accelerator"
  $run = Start-CapturedProcess $Package.handy @(
    "--transcribe-file", $Fixture.wav_path,
    "--model", $Model.id,
    "--ort-accelerator", $Accelerator,
    "--repeat", "$Repeat",
    "--json"
  ) $prefix @{ RUST_LOG = "info"; ORT_LOG = "info" }

  $bestVram = $null
  $deadline = [DateTime]::UtcNow.AddMinutes(30)
  while (-not $run.process.HasExited) {
    if ($MonitorVram) {
      $sample = Get-VramSample -ProcessId $run.process.Id
      if ($sample -and (-not $bestVram -or
          $sample.used_memory_mb -gt $bestVram.used_memory_mb)) {
        $bestVram = $sample
      }
    }
    if ([DateTime]::UtcNow -gt $deadline) {
      $run.process.Kill($true)
      throw "benchmark timed out: $($Model.id) $Accelerator"
    }
    Start-Sleep -Milliseconds 100
    $run.process.Refresh()
  }
  $result = Complete-CapturedProcess $run 30
  if ($result.exit_code -ne 0) {
    throw "$($Model.id) $Accelerator benchmark exited $($result.exit_code): $($result.stderr)"
  }
  $parsed = $result.stdout | ConvertFrom-Json
  if (@($parsed.transcribe_ms).Count -lt $Repeat) {
    throw "$($Model.id) $Accelerator returned fewer than $Repeat measured runs"
  }
  if ([string]::IsNullOrWhiteSpace([string]$parsed.text)) {
    throw "$($Model.id) $Accelerator returned empty text"
  }
  if ($parsed.ort_selected -ne $Accelerator -or $parsed.ort_fallback_reason) {
    throw "$($Model.id) $Accelerator did not bind requested ORT accelerator"
  }
  if ($Accelerator -eq "cuda" -and
      $result.stderr -notmatch "CUDAExecutionProvider registration probe succeeded") {
    throw "$($Model.id) CUDA run lacks provider registration proof"
  }
  if ($MonitorVram -and (-not $bestVram -or $bestVram.used_memory_mb -le 0)) {
    throw "nvidia-smi did not observe non-zero VRAM for exact Handy PID $($result.pid)"
  }

  $reference = Normalize-Transcript $Fixture.reference
  $hypothesis = Normalize-Transcript ([string]$parsed.text)
  $wer = Get-WordErrorRate $reference $hypothesis
  if ($wer -gt 0.50) {
    throw "$($Model.id) $Accelerator WER $wer exceeds 0.50"
  }
  return [pscustomobject]@{
    model = $Model.id
    accelerator = $Accelerator
    pid = $result.pid
    load_ms = [long]$parsed.load_ms
    transcribe_ms = @($parsed.transcribe_ms | ForEach-Object { [long]$_ })
    best_ms = [long]$parsed.best_ms
    audio_secs = [double]$parsed.audio_secs
    rtf = [double]$parsed.rtf
    transcript = [string]$parsed.text
    normalized_reference = $reference
    normalized_hypothesis = $hypothesis
    wer = [Math]::Round($wer, 6)
    ort_selected = [string]$parsed.ort_selected
    provider_log = if ($Accelerator -eq "cuda") {
      "CUDAExecutionProvider registration probe succeeded"
    } else { $null }
    vram = $bestVram
  }
}

New-Item -ItemType Directory -Path $CacheRoot, $EvidenceDir -Force | Out-Null
$buildScript = Join-Path $PSScriptRoot "build-windows-cuda.ps1"
if (-not (Test-Path -LiteralPath $buildScript -PathType Leaf)) {
  throw "missing build-windows-cuda.ps1"
}

if ($Mode -eq "All") {
  $buildOutput = @(& $buildScript -Mode All -CacheRoot $BuildCacheRoot `
    -OutputDir (Join-Path $repoRoot "dist\windows-cuda") -Json)
  $buildSucceeded = $?
  if (-not $buildSucceeded) { throw "native Windows CUDA build/audit failed" }
  if ($buildOutput.Count -eq 0) { throw "native Windows CUDA build returned no summary" }
  $version = (Get-Content -LiteralPath (Join-Path $repoRoot "src-tauri\tauri.conf.json") -Raw |
    ConvertFrom-Json).version
  $Nsis = Join-Path $repoRoot "dist\windows-cuda\Handy_${version}_x64-cuda13-setup.exe"
  $Msi = Join-Path $repoRoot "dist\windows-cuda\Handy_${version}_x64-cuda13_en-US.msi"
}
if (-not $Nsis -or -not $Msi) { throw "Verify mode requires -Nsis and -Msi" }
$Nsis = [System.IO.Path]::GetFullPath($Nsis)
$Msi = [System.IO.Path]::GetFullPath($Msi)
if (-not (Test-Path -LiteralPath $Nsis -PathType Leaf) -or
    -not (Test-Path -LiteralPath $Msi -PathType Leaf)) {
  throw "CUDA NSIS/MSI artifact is missing"
}

$artifacts = @(
  [pscustomobject]@{
    kind = "nsis"
    path = $Nsis
    bytes = (Get-Item -LiteralPath $Nsis).Length
    sha256 = Get-Sha256 $Nsis
  },
  [pscustomobject]@{
    kind = "msi"
    path = $Msi
    bytes = (Get-Item -LiteralPath $Msi).Length
    sha256 = Get-Sha256 $Msi
  }
)
Write-JsonFile $artifacts (Join-Path $EvidenceDir "artifacts.json")

$workRoot = Join-Path $CacheRoot "work"
$packages = @(Expand-Packages $Nsis $Msi $workRoot)
$packageAudits = @($packages | ForEach-Object { Get-PackageAudit $_ $buildScript })
Write-JsonFile $packageAudits (Join-Path $EvidenceDir "package-audits.json")

$launches = @($packages | ForEach-Object { Test-PackageLaunch $_ $EvidenceDir })
Write-JsonFile $launches (Join-Path $EvidenceDir "package-launches.json")

$negative = Test-MissingProviderFailure $packages[0] (Join-Path $workRoot "negative") $EvidenceDir
Write-JsonFile $negative (Join-Path $EvidenceDir "missing-provider.json")

$fixture = Get-DeterministicFixture $FixtureManifest
Write-JsonFile $fixture (Join-Path $EvidenceDir "fixture.json")
$cachedModels = Get-ModelFiles
foreach ($package in $packages) { Materialize-Models $package $cachedModels }

$benchmarks = @()
foreach ($model in $models) {
  $cpu = Invoke-Benchmark $packages[0] $model "cpu" $fixture $EvidenceDir
  $cuda = Invoke-Benchmark $packages[0] $model "cuda" $fixture $EvidenceDir
  if ($model.id -eq "gigaam-multilingual-600m-fp32-cuda") {
    $vramProbe = Invoke-Benchmark $packages[0] $model "cuda" $fixture $EvidenceDir -MonitorVram
    $cuda.vram = $vramProbe.vram
  }
  if (($cuda.wer - $cpu.wer) -gt 0.02) {
    throw "$($model.id) CUDA WER regression exceeds 0.02"
  }
  if ($cuda.best_ms -ge $cpu.best_ms) {
    throw "$($model.id) CUDA best time $($cuda.best_ms)ms is not below CPU $($cpu.best_ms)ms"
  }
  $benchmarks += [pscustomobject]@{
    model = $model.id
    cpu = $cpu
    cuda = $cuda
    speed_ratio = [Math]::Round($cpu.best_ms / [double]$cuda.best_ms, 3)
    cuda_wer_regression = [Math]::Round($cuda.wer - $cpu.wer, 6)
  }
}
Write-JsonFile $benchmarks (Join-Path $EvidenceDir "benchmarks.json")

$vram = $benchmarks | Where-Object model -eq "gigaam-multilingual-600m-fp32-cuda" |
  Select-Object -ExpandProperty cuda | Select-Object -ExpandProperty vram
Write-JsonFile $vram (Join-Path $EvidenceDir "vram.json")

$result = [ordered]@{
  plan = $plan
  artifacts = $artifacts
  package_audits = $packageAudits
  package_launches = $launches
  missing_provider = $negative
  fixture = $fixture
  benchmarks = $benchmarks
  vram = $vram
  evidence_dir = $EvidenceDir
}
Write-JsonFile $result (Join-Path $EvidenceDir "verification.json")

if ($Json) { $result | ConvertTo-Json -Depth 15 } else { $result }
