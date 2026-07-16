[CmdletBinding()]
param(
  [ValidateSet("Plan", "Prepare", "Build", "Audit", "All")]
  [string]$Mode = "All",
  [string]$CacheRoot = (Join-Path $env:LOCALAPPDATA "gigatype-cuda-build"),
  [string]$OutputDir,
  [string]$PackageRoot,
  [string]$ExpectedStagedRuntimeDir,
  [string]$Nsis,
  [string]$Msi,
  [ValidateSet("Cuda", "Cpu")]
  [string]$Edition = "Cuda",
  [string]$GithubEnvironment,
  [switch]$Json
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "windows-package-helpers.ps1")

$repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".."))
$appConfig = Get-Content -LiteralPath (Join-Path $repoRoot "src-tauri\tauri.conf.json") -Raw |
  ConvertFrom-Json
$productName = [string]$appConfig.productName
$version = [string]$appConfig.version
$executableName = "$productName.exe"
if (-not $productName -or -not $version) {
  throw "tauri.conf.json must define productName and version"
}
if (-not $ExpectedStagedRuntimeDir) {
  $ExpectedStagedRuntimeDir = Join-Path $repoRoot "src-tauri\transcribe-libs"
}
$ExpectedStagedRuntimeDir = [System.IO.Path]::GetFullPath($ExpectedStagedRuntimeDir)
if (-not $OutputDir) {
  $outputName = if ($Edition -eq "Cuda") { "windows-cuda" } else { "windows-cpu" }
  $OutputDir = Join-Path $repoRoot "dist\$outputName"
}
$CacheRoot = [System.IO.Path]::GetFullPath($CacheRoot)
$OutputDir = [System.IO.Path]::GetFullPath($OutputDir)

$ortVersion = "1.24.2"
$cpuOrtAsset = "onnxruntime-win-x64-1.24.2.zip"
$cpuOrtSha256 = "8e3e9c826375352e29cb2614fe44f3d7a4b0ff7b8028ad7a456af9d949a7e8b0"
$cpuOrtSize = 74075355
$cudaOrtAsset = "onnxruntime-win-x64-gpu_cuda13-1.24.2.zip"
$cudaOrtSha256 = "72207a283ec9886e1968a4183636a7665c78e2154d4f4adc16e61193dd7a74f1"
$ortAsset = if ($Edition -eq "Cuda") { $cudaOrtAsset } else { $cpuOrtAsset }
$ortSha256 = if ($Edition -eq "Cuda") { $cudaOrtSha256 } else { $cpuOrtSha256 }
$ortUrl = "https://github.com/microsoft/onnxruntime/releases/download/v$ortVersion/$ortAsset"
$cudaManifestName = "redistrib_13.0.2.json"
$cudaManifestSha256 = "fce66717a81c510ffeb89ecc3e79849ab34af3b80139f750876d9033e31d71c2"
$cudaManifestUrl = "https://developer.download.nvidia.com/compute/cuda/redist/$cudaManifestName"
$cudaComponents = @("cuda_cudart", "cuda_nvrtc", "libcublas", "libcufft", "libnvjitlink")
$cudnnVersion = "9.16.0.29"
$cudnnManifestName = "redistrib_9.16.0.json"
$cudnnManifestSha256 = "c95167877ac0ded30a29accc9d337a5e60cd70d1a01a3492de56624b39eab868"
$cudnnManifestUrl = "https://developer.download.nvidia.com/compute/cudnn/redist/$cudnnManifestName"
$cudnnSha256 = "606c405a46e55bec01be8dd81092d238900f4028fee10a7ed1bc32cd5e23714e"
$artifactNames = if ($Edition -eq "Cuda") {
  [ordered]@{
    nsis = "$($productName)_${version}_x64-cuda13-setup.exe"
    msi = "$($productName)_${version}_x64-cuda13_en-US.msi"
  }
} else {
  [ordered]@{
    nsis = "$($productName)_${version}_x64-setup.exe"
    msi = "$($productName)_${version}_x64_en-US.msi"
  }
}

$plan = [ordered]@{
  product_name = $productName
  version = $version
  executable = $executableName
  edition = if ($Edition -eq "Cuda") { "cuda13" } else { "cpu" }
  artifacts = $artifactNames
  ort = [ordered]@{
    version = $ortVersion
    asset = $ortAsset
    url = $ortUrl
    sha256 = $ortSha256
  }
  cuda = if ($Edition -eq "Cuda") {
    [ordered]@{
      manifest = $cudaManifestName
      manifest_url = $cudaManifestUrl
      manifest_sha256 = $cudaManifestSha256
      components = $cudaComponents
    }
  } else { $null }
  cudnn = if ($Edition -eq "Cuda") {
    [ordered]@{
      version = $cudnnVersion
      manifest = $cudnnManifestName
      manifest_url = $cudnnManifestUrl
      manifest_sha256 = $cudnnManifestSha256
      sha256 = $cudnnSha256
    }
  } else { $null }
}

if ($Mode -eq "Plan") {
  if ($Json) {
    $plan | ConvertTo-Json -Depth 8
  } else {
    $plan
  }
  exit 0
}

$script:downloadCount = 0
$script:cacheHitCount = 0

function Get-Sha256 {
  param([Parameter(Mandatory)][string]$Path)
  return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Get-VerifiedDownload {
  param(
    [Parameter(Mandatory)][string]$Uri,
    [Parameter(Mandatory)][string]$Path,
    [Parameter(Mandatory)][string]$Sha256,
    [long]$ExpectedSize = 0
  )

  $parent = Split-Path -Parent $Path
  New-Item -ItemType Directory -Path $parent -Force | Out-Null
  if (Test-Path -LiteralPath $Path -PathType Leaf) {
    $sizeMatches = $ExpectedSize -le 0 -or (Get-Item -LiteralPath $Path).Length -eq $ExpectedSize
    if ($sizeMatches -and (Get-Sha256 $Path) -eq $Sha256) {
      $script:cacheHitCount++
      Write-Host "cache hit: $(Split-Path -Leaf $Path)"
      return
    }
    Assert-OwnedPath -Path $Path -OwnedRoot $CacheRoot
    Remove-Item -LiteralPath $Path -Force
  }

  $partial = "$Path.download"
  Assert-OwnedPath -Path $partial -OwnedRoot $CacheRoot
  if (Test-Path -LiteralPath $partial) {
    Remove-Item -LiteralPath $partial -Force
  }
  Write-Host "download: $Uri"
  Invoke-WebRequest -Uri $Uri -OutFile $partial
  if ($ExpectedSize -gt 0 -and (Get-Item -LiteralPath $partial).Length -ne $ExpectedSize) {
    throw "downloaded size mismatch for $(Split-Path -Leaf $Path)"
  }
  $actualSha256 = Get-Sha256 $partial
  if ($actualSha256 -ne $Sha256) {
    throw "SHA256 mismatch for $(Split-Path -Leaf $Path): expected $Sha256, got $actualSha256"
  }
  Move-Item -LiteralPath $partial -Destination $Path
  $script:downloadCount++
}

function Expand-VerifiedArchive {
  param(
    [Parameter(Mandatory)][string]$Archive,
    [Parameter(Mandatory)][string]$Destination,
    [Parameter(Mandatory)][string]$Sha256
  )
  $marker = Join-Path $Destination ".handy-sha256"
  if ((Test-Path -LiteralPath $marker -PathType Leaf) -and
      ((Get-Content -LiteralPath $marker -Raw).Trim() -eq $Sha256)) {
    return
  }
  Reset-OwnedDirectory -Path $Destination -OwnedRoot $CacheRoot
  Expand-Archive -LiteralPath $Archive -DestinationPath $Destination -Force
  Set-Content -LiteralPath $marker -Value $Sha256 -NoNewline
}

function Copy-UniqueDll {
  param(
    [Parameter(Mandatory)][string]$Source,
    [Parameter(Mandatory)][string]$DestinationDirectory
  )
  $destination = Join-Path $DestinationDirectory (Split-Path -Leaf $Source)
  if (Test-Path -LiteralPath $destination) {
    if ((Get-Sha256 $Source) -ne (Get-Sha256 $destination)) {
      throw "runtime DLL collision with different content: $(Split-Path -Leaf $Source)"
    }
    return
  }
  Copy-Item -LiteralPath $Source -Destination $destination
}

function Copy-ArchiveRuntime {
  param(
    [Parameter(Mandatory)][string]$ExtractedRoot,
    [Parameter(Mandatory)][string]$RuntimeDirectory
  )
  $dlls = @(Get-ChildItem -LiteralPath $ExtractedRoot -Filter "*.dll" -File -Recurse)
  if ($dlls.Count -eq 0) {
    throw "archive contains no runtime DLLs: $ExtractedRoot"
  }
  foreach ($dll in $dlls) {
    Copy-UniqueDll $dll.FullName $RuntimeDirectory
  }
}

function Copy-SelectedArchiveRuntime {
  param(
    [Parameter(Mandatory)][string]$ExtractedRoot,
    [Parameter(Mandatory)][string[]]$Names,
    [Parameter(Mandatory)][string]$RuntimeDirectory
  )
  foreach ($name in $Names) {
    $source = Get-ChildItem -LiteralPath $ExtractedRoot -Filter $name -File -Recurse |
      Select-Object -First 1
    if (-not $source) { throw "archive is missing required runtime DLL $name" }
    Copy-UniqueDll $source.FullName $RuntimeDirectory
  }
}

function Copy-ArchiveLicense {
  param(
    [Parameter(Mandatory)][string]$ExtractedRoot,
    [Parameter(Mandatory)][string]$Name,
    [Parameter(Mandatory)][string]$LicenseDirectory
  )
  $license = Get-ChildItem -LiteralPath $ExtractedRoot -File -Recurse |
    Where-Object { $_.Name -in @("LICENSE", "LICENSE.txt") } |
    Select-Object -First 1
  if (-not $license) {
    throw "archive license missing: $Name"
  }
  Copy-Item -LiteralPath $license.FullName -Destination (Join-Path $LicenseDirectory "$Name-LICENSE.txt")
}

function Find-Dumpbin {
  $command = Get-Command "dumpbin.exe" -ErrorAction SilentlyContinue
  if ($command) { return $command.Source }

  $roots = @(
    (Join-Path $env:ProgramFiles "Microsoft Visual Studio"),
    (Join-Path ${env:ProgramFiles(x86)} "Microsoft Visual Studio")
  ) | Where-Object { $_ -and (Test-Path -LiteralPath $_) }
  $candidate = foreach ($root in $roots) {
    Get-ChildItem -LiteralPath $root -Filter "dumpbin.exe" -File -Recurse -ErrorAction SilentlyContinue |
      Where-Object { $_.FullName -match "Hostx64\\x64\\dumpbin\.exe$" }
  }
  $selected = $candidate | Sort-Object FullName | Select-Object -Last 1
  if (-not $selected) { throw "dumpbin.exe not found; install Visual Studio C++ tools" }
  return $selected.FullName
}

function Get-PeDependencies {
  param(
    [Parameter(Mandatory)][string]$Dumpbin,
    [Parameter(Mandatory)][string]$Path
  )
  $output = @(& $Dumpbin /dependents $Path 2>&1)
  $nativeSucceeded = $?
  if (-not $nativeSucceeded) {
    throw "dumpbin /dependents failed for $Path"
  }
  return @($output |
    ForEach-Object { "$($_)".Trim() } |
    Where-Object { $_ -match "^[A-Za-z0-9_.+\-]+\.dll$" })
}

function Test-PermittedSystemDll {
  param([Parameter(Mandatory)][string]$Name)
  $lower = $Name.ToLowerInvariant()
  if ($lower -like "api-ms-win-*.dll" -or $lower -like "ext-ms-win-*.dll") { return $true }
  if ($lower -in @("nvcuda.dll", "nvapi64.dll", "vulkan-1.dll")) { return $true }
  $system = @(
    "advapi32.dll", "bcrypt.dll", "bcryptprimitives.dll", "cfgmgr32.dll", "combase.dll", "comctl32.dll",
    "comdlg32.dll", "crypt32.dll", "dbghelp.dll", "dwmapi.dll", "dxgi.dll",
    "gdi32.dll", "imm32.dll", "iphlpapi.dll", "kernel32.dll", "msvcrt.dll",
    "normaliz.dll", "ntdll.dll", "ole32.dll", "oleaut32.dll", "powrprof.dll",
    "propsys.dll", "rpcrt4.dll", "secur32.dll", "setupapi.dll", "shell32.dll",
    "shlwapi.dll", "user32.dll", "userenv.dll", "ucrtbase.dll", "version.dll",
    "winhttp.dll", "winmm.dll", "wintrust.dll", "ws2_32.dll", "wtsapi32.dll",
    "d3d11.dll", "d3d12.dll", "dxcore.dll", "dwrite.dll", "windowscodecs.dll",
    "msvcp140.dll", "msvcp140_1.dll", "msvcp140_2.dll", "vcomp140.dll",
    "vcruntime140.dll", "vcruntime140_1.dll"
  )
  return $lower -in $system
}

function Test-PeClosure {
  param([Parameter(Mandatory)][string]$Root)
  $dumpbin = Find-Dumpbin
  $peFiles = @(Get-ChildItem -LiteralPath $Root -File -Recurse |
    Where-Object { $_.Extension -in @(".dll", ".exe") })
  $available = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
  foreach ($file in $peFiles) { [void]$available.Add($file.Name) }

  $unresolved = [System.Collections.Generic.List[string]]::new()
  foreach ($file in $peFiles) {
    foreach ($dependency in (Get-PeDependencies $dumpbin $file.FullName)) {
      if (-not $available.Contains($dependency) -and -not (Test-PermittedSystemDll $dependency)) {
        $unresolved.Add("$($file.Name) -> $dependency")
      }
    }
  }
  if ($unresolved.Count -gt 0) {
    throw "unresolved non-system PE imports:`n$($unresolved -join [Environment]::NewLine)"
  }
  return [pscustomobject]@{ files = $peFiles.Count; unresolved = 0 }
}

function Prepare-CpuRuntime {
  $downloads = Join-Path $CacheRoot "downloads"
  $extracted = Join-Path $CacheRoot "extracted"
  $runtime = Join-Path $CacheRoot "runtime-cpu"
  New-Item -ItemType Directory -Path $downloads, $extracted -Force | Out-Null

  $ortArchive = Join-Path $downloads $cpuOrtAsset
  Get-VerifiedDownload $ortUrl $ortArchive $cpuOrtSha256 $cpuOrtSize
  $ortExtracted = Join-Path $extracted "ort-$ortVersion-cpu"
  Expand-VerifiedArchive $ortArchive $ortExtracted $cpuOrtSha256

  $ortRoot = Join-Path $ortExtracted "onnxruntime-win-x64-$ortVersion"
  if (-not (Test-Path -LiteralPath $ortRoot -PathType Container)) {
    throw "extracted CPU ORT root not found: $ortRoot"
  }
  $ortLib = Join-Path $ortRoot "lib"
  $onnxRuntime = Join-Path $ortLib "onnxruntime.dll"
  if (-not (Test-Path -LiteralPath $onnxRuntime -PathType Leaf)) {
    throw "CPU ORT archive is missing onnxruntime.dll"
  }

  Reset-OwnedDirectory -Path $runtime -OwnedRoot $CacheRoot
  $licenses = Join-Path $runtime "licenses"
  New-Item -ItemType Directory -Path $licenses -Force | Out-Null
  Copy-Item -LiteralPath $onnxRuntime -Destination $runtime
  Copy-Item -LiteralPath (Join-Path $ortRoot "LICENSE") -Destination (Join-Path $licenses "onnxruntime-LICENSE.txt")
  Copy-Item -LiteralPath (Join-Path $ortRoot "ThirdPartyNotices.txt") -Destination (Join-Path $licenses "onnxruntime-ThirdPartyNotices.txt")

  $closure = Test-PeClosure $runtime
  if ($GithubEnvironment) {
    Add-Content -LiteralPath $GithubEnvironment -Value "ORT_LIB_LOCATION=$ortLib"
    Add-Content -LiteralPath $GithubEnvironment -Value "ORT_PREFER_DYNAMIC_LINK=1"
  }

  return [pscustomobject]@{
    cache_root = $CacheRoot
    runtime_dir = $runtime
    ort_lib = $ortLib
    downloads = $script:downloadCount
    cache_hits = $script:cacheHitCount
    dll_count = 1
    pe_files = $closure.files
    unresolved_imports = $closure.unresolved
    dlls = @([pscustomobject]@{
      name = "onnxruntime.dll"
      bytes = (Get-Item -LiteralPath $onnxRuntime).Length
      sha256 = Get-Sha256 $onnxRuntime
    })
  }
}

function Prepare-CudaRuntime {
  $downloads = Join-Path $CacheRoot "downloads"
  $extracted = Join-Path $CacheRoot "extracted"
  $runtime = Join-Path $CacheRoot "runtime"
  New-Item -ItemType Directory -Path $downloads, $extracted -Force | Out-Null

  $ortArchive = Join-Path $downloads $ortAsset
  Get-VerifiedDownload $ortUrl $ortArchive $ortSha256 288348147
  $ortExtracted = Join-Path $extracted "ort-$ortVersion-cuda13"
  Expand-VerifiedArchive $ortArchive $ortExtracted $ortSha256

  $cudaManifestPath = Join-Path $downloads $cudaManifestName
  Get-VerifiedDownload $cudaManifestUrl $cudaManifestPath $cudaManifestSha256
  $cudaManifest = Get-Content -LiteralPath $cudaManifestPath -Raw | ConvertFrom-Json -AsHashtable

  $componentRoots = [ordered]@{}
  foreach ($component in $cudaComponents) {
    $entry = $cudaManifest[$component]
    if (-not $entry) { throw "CUDA manifest is missing component $component" }
    $platform = $entry["windows-x86_64"]
    if (-not $platform) { throw "CUDA component $component has no windows-x86_64 archive" }
    $relativePath = [string]$platform["relative_path"]
    $archive = Join-Path $downloads (Split-Path -Leaf $relativePath)
    $uri = "https://developer.download.nvidia.com/compute/cuda/redist/$relativePath"
    Get-VerifiedDownload $uri $archive ([string]$platform["sha256"]) ([long]$platform["size"])
    $componentExtracted = Join-Path $extracted $component
    Expand-VerifiedArchive $archive $componentExtracted ([string]$platform["sha256"])
    $componentRoots[$component] = $componentExtracted
  }

  $cudnnManifestPath = Join-Path $downloads $cudnnManifestName
  Get-VerifiedDownload $cudnnManifestUrl $cudnnManifestPath $cudnnManifestSha256
  $cudnnManifest = Get-Content -LiteralPath $cudnnManifestPath -Raw | ConvertFrom-Json -AsHashtable
  if ([string]$cudnnManifest["cudnn"]["version"] -ne $cudnnVersion) {
    throw "cuDNN manifest version mismatch"
  }
  $cudnnPlatform = $cudnnManifest["cudnn"]["windows-x86_64"]["cuda13"]
  if ([string]$cudnnPlatform["sha256"] -ne $cudnnSha256) {
    throw "cuDNN manifest archive SHA256 does not match pinned value"
  }
  $cudnnRelativePath = [string]$cudnnPlatform["relative_path"]
  $cudnnArchive = Join-Path $downloads (Split-Path -Leaf $cudnnRelativePath)
  $cudnnUri = "https://developer.download.nvidia.com/compute/cudnn/redist/$cudnnRelativePath"
  Get-VerifiedDownload $cudnnUri $cudnnArchive $cudnnSha256 ([long]$cudnnPlatform["size"])
  $cudnnExtracted = Join-Path $extracted "cudnn-$cudnnVersion-cuda13"
  Expand-VerifiedArchive $cudnnArchive $cudnnExtracted $cudnnSha256

  Reset-OwnedDirectory -Path $runtime -OwnedRoot $CacheRoot
  $licenses = Join-Path $runtime "licenses"
  New-Item -ItemType Directory -Path $licenses -Force | Out-Null

  $ortRoot = Get-ChildItem -LiteralPath $ortExtracted -Directory |
    Where-Object { $_.Name -like "onnxruntime-win-x64-gpu-*" } |
    Select-Object -First 1
  if (-not $ortRoot) { throw "extracted ORT root not found" }
  $ortLib = Join-Path $ortRoot.FullName "lib"
  foreach ($name in @("onnxruntime.dll", "onnxruntime_providers_shared.dll", "onnxruntime_providers_cuda.dll")) {
    $source = Join-Path $ortLib $name
    if (-not (Test-Path -LiteralPath $source -PathType Leaf)) { throw "ORT archive missing $name" }
    Copy-UniqueDll $source $runtime
  }
  Copy-Item -LiteralPath (Join-Path $ortRoot.FullName "LICENSE") -Destination (Join-Path $licenses "onnxruntime-LICENSE.txt")
  Copy-Item -LiteralPath (Join-Path $ortRoot.FullName "ThirdPartyNotices.txt") -Destination (Join-Path $licenses "onnxruntime-ThirdPartyNotices.txt")

  $componentDlls = [ordered]@{
    cuda_cudart = @("cudart64_13.dll")
    cuda_nvrtc = @("nvrtc64_130_0.dll", "nvrtc-builtins64_130.dll")
    libcublas = @("cublas64_13.dll", "cublasLt64_13.dll")
    libcufft = @("cufft64_12.dll")
    libnvjitlink = @("nvJitLink_130_0.dll")
  }
  foreach ($component in $componentRoots.Keys) {
    Copy-SelectedArchiveRuntime $componentRoots[$component] $componentDlls[$component] $runtime
    Copy-ArchiveLicense $componentRoots[$component] $component $licenses
  }
  Copy-ArchiveRuntime $cudnnExtracted $runtime
  Copy-ArchiveLicense $cudnnExtracted "cudnn" $licenses

  $noticeSource = Join-Path $repoRoot "src-tauri\cuda-resources\THIRD_PARTY_NOTICES-CUDA.txt"
  if (-not (Test-Path -LiteralPath $noticeSource -PathType Leaf)) {
    throw "tracked CUDA notice source is missing: $noticeSource"
  }
  Copy-Item -LiteralPath $noticeSource -Destination (Join-Path $runtime "THIRD_PARTY_NOTICES-CUDA.txt")

  $requiredDlls = @(
    "onnxruntime.dll", "onnxruntime_providers_shared.dll", "onnxruntime_providers_cuda.dll",
    "cublasLt64_13.dll", "cublas64_13.dll", "cudart64_13.dll", "cufft64_12.dll",
    "cudnn64_9.dll", "nvrtc64_130_0.dll", "nvJitLink_130_0.dll"
  )
  foreach ($name in $requiredDlls) {
    if (-not (Test-Path -LiteralPath (Join-Path $runtime $name) -PathType Leaf)) {
      throw "prepared CUDA runtime is missing required DLL $name"
    }
  }

  $closure = Test-PeClosure $runtime
  if ($GithubEnvironment) {
    Add-Content -LiteralPath $GithubEnvironment -Value "ORT_LIB_LOCATION=$ortLib"
    Add-Content -LiteralPath $GithubEnvironment -Value "ORT_PREFER_DYNAMIC_LINK=1"
    Add-Content -LiteralPath $GithubEnvironment -Value "HANDY_CUDA_RUNTIME_DIR=$runtime"
  }

  $dlls = @(Get-ChildItem -LiteralPath $runtime -Filter "*.dll" -File | Sort-Object Name)
  return [pscustomobject]@{
    cache_root = $CacheRoot
    runtime_dir = $runtime
    ort_lib = $ortLib
    downloads = $script:downloadCount
    cache_hits = $script:cacheHitCount
    dll_count = $dlls.Count
    pe_files = $closure.files
    unresolved_imports = $closure.unresolved
    dlls = @($dlls | ForEach-Object {
      [pscustomobject]@{ name = $_.Name; bytes = $_.Length; sha256 = Get-Sha256 $_.FullName }
    })
  }
}

function Find-VcVars64 {
  $candidate = Get-ChildItem -LiteralPath (Join-Path $env:ProgramFiles "Microsoft Visual Studio") `
    -Filter "vcvars64.bat" -File -Recurse -ErrorAction SilentlyContinue |
    Sort-Object FullName | Select-Object -Last 1
  if (-not $candidate) { throw "vcvars64.bat not found" }
  return $candidate.FullName
}

function Find-VcRedistDirectories {
  $msvcRoot = Join-Path $env:ProgramFiles "Microsoft Visual Studio"
  $crt = Get-ChildItem -LiteralPath $msvcRoot -Filter "msvcp140.dll" -File -Recurse -ErrorAction SilentlyContinue |
    Where-Object { $_.FullName -match "\\VC\\Redist\\MSVC\\.*\\x64\\Microsoft\.VC.*\.CRT\\msvcp140\.dll$" } |
    Sort-Object FullName | Select-Object -Last 1
  $omp = Get-ChildItem -LiteralPath $msvcRoot -Filter "vcomp140.dll" -File -Recurse -ErrorAction SilentlyContinue |
    Where-Object { $_.FullName -match "\\VC\\Redist\\MSVC\\.*\\x64\\Microsoft\.VC.*\.OpenMP\\vcomp140\.dll$" } |
    Sort-Object FullName | Select-Object -Last 1
  if (-not $crt -or -not $omp) { throw "x64 VC++ CRT/OpenMP redistributable directories not found" }
  return "$(Split-Path -Parent $crt.FullName);$(Split-Path -Parent $omp.FullName)"
}

function Find-Bun {
  $command = Get-Command "bun.exe" -ErrorAction SilentlyContinue
  if ($command) { return $command.Source }
  $candidate = Get-ChildItem -LiteralPath (Join-Path $env:LOCALAPPDATA "Microsoft\WinGet\Packages") `
    -Filter "bun.exe" -File -Recurse -ErrorAction SilentlyContinue |
    Sort-Object FullName | Select-Object -Last 1
  if (-not $candidate) { throw "bun.exe not found" }
  return $candidate.FullName
}

function Find-Cargo {
  $command = Get-Command "cargo.exe" -ErrorAction SilentlyContinue
  if ($command) { return $command.Source }
  $candidate = Join-Path $env:USERPROFILE ".cargo\bin\cargo.exe"
  if (-not (Test-Path -LiteralPath $candidate -PathType Leaf)) {
    throw "cargo.exe not found"
  }
  return $candidate
}

function Find-WindowsLinkDirectories {
  $sdkRoot = Join-Path ${env:ProgramFiles(x86)} "Windows Kits\10\lib"
  $kernel32 = Get-ChildItem -Path (Join-Path $sdkRoot "*\um\x64\kernel32.Lib") -File `
    -ErrorAction SilentlyContinue | Sort-Object FullName | Select-Object -Last 1
  if (-not $kernel32) { throw "Windows SDK x64 kernel32.Lib not found" }

  $sdkVersionRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $kernel32.FullName))
  $ucrtDirectory = Join-Path $sdkVersionRoot "ucrt\x64"
  if (-not (Test-Path -LiteralPath (Join-Path $ucrtDirectory "ucrt.Lib") -PathType Leaf)) {
    throw "Windows SDK x64 ucrt.Lib not found"
  }

  $msvcPattern = Join-Path $env:ProgramFiles `
    "Microsoft Visual Studio\2022\*\VC\Tools\MSVC\*\lib\x64\libcmt.Lib"
  $libcmt = Get-ChildItem -Path $msvcPattern -File -ErrorAction SilentlyContinue |
    Sort-Object FullName | Select-Object -Last 1
  if (-not $libcmt) { throw "MSVC x64 libcmt.Lib not found" }

  return @($libcmt.Directory.FullName, $ucrtDirectory, $kernel32.Directory.FullName)
}

function Find-WindowsIncludeDirectories {
  $sdkIncludeRoot = Join-Path ${env:ProgramFiles(x86)} "Windows Kits\10\Include"
  $windowsHeader = Get-ChildItem -Path (Join-Path $sdkIncludeRoot "*\um\windows.h") -File `
    -ErrorAction SilentlyContinue | Sort-Object FullName | Select-Object -Last 1
  if (-not $windowsHeader) { throw "Windows SDK windows.h not found" }
  $sdkVersionRoot = Split-Path -Parent (Split-Path -Parent $windowsHeader.FullName)

  $msvcPattern = Join-Path $env:ProgramFiles `
    "Microsoft Visual Studio\2022\*\VC\Tools\MSVC\*\include\vcruntime.h"
  $msvcHeader = Get-ChildItem -Path $msvcPattern -File -ErrorAction SilentlyContinue |
    Sort-Object FullName | Select-Object -Last 1
  if (-not $msvcHeader) { throw "MSVC vcruntime.h not found" }

  $directories = @($msvcHeader.Directory.FullName)
  foreach ($name in @("ucrt", "shared", "um", "winrt", "cppwinrt")) {
    $directory = Join-Path $sdkVersionRoot $name
    if (Test-Path -LiteralPath $directory -PathType Container) {
      $directories += $directory
    }
  }
  return $directories
}

function Build-WindowsInstallers {
  param(
    [Parameter(Mandatory)]$Prepared,
    [Parameter(Mandatory)][ValidateSet("Cuda", "Cpu")][string]$PackageEdition
  )
  $vcvars = Find-VcVars64
  $redist = Find-VcRedistDirectories
  $bun = Find-Bun
  $cargo = Find-Cargo
  $linkDirectories = Find-WindowsLinkDirectories
  $encodedRustFlags = ($linkDirectories | ForEach-Object { "-Lnative=$_" }) -join [char]0x1f
  $includeDirectories = Find-WindowsIncludeDirectories
  $compilerFlags = ($includeDirectories | ForEach-Object { "/I`"$_`"" }) -join " "
  $bunDir = Split-Path -Parent $bun
  $tauriEntrypoint = Join-Path $repoRoot "node_modules\@tauri-apps\cli\tauri.js"
  if (-not (Test-Path -LiteralPath $tauriEntrypoint -PathType Leaf)) {
    throw "Tauri CLI entrypoint not found; run bun install"
  }
  $cargoWrapper = Join-Path $CacheRoot "cargo.cmd"
  @(
    "@echo off",
    "call `"$vcvars`" >nul",
    "if errorlevel 1 exit /b %errorlevel%",
    "`"$cargo`" %*"
  ) | Set-Content -LiteralPath $cargoWrapper -Encoding ascii
  $editionSlug = $PackageEdition.ToLowerInvariant()
  $targetDir = Join-Path $CacheRoot "cargo-target-$editionSlug"
  New-Item -ItemType Directory -Path $targetDir -Force | Out-Null

  $configPath = Join-Path $CacheRoot "tauri.$editionSlug-windows.conf.json"
  @{
    build = @{
      beforeBuildCommand = $null
    }
    bundle = @{
      createUpdaterArtifacts = $false
      windows = @{ signCommand = $null }
    }
  } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $configPath

  $vulkanSdk = $env:VULKAN_SDK
  if (-not $vulkanSdk) {
    $vulkanSdk = Get-ChildItem -LiteralPath "C:\VulkanSDK" -Directory -ErrorAction SilentlyContinue |
      Sort-Object Name | Select-Object -Last 1 -ExpandProperty FullName
  }
  if (-not $vulkanSdk) { throw "Vulkan SDK not found" }

  $cmakePrefix = $env:CMAKE_PREFIX_PATH
  if (-not $cmakePrefix) {
    $knownPrefix = Join-Path $env:LOCALAPPDATA "handy-vcpkg\manifest\vcpkg_installed\x64-windows"
    if (Test-Path -LiteralPath $knownPrefix) { $cmakePrefix = $knownPrefix }
  }
  if (-not $cmakePrefix) { throw "CMAKE_PREFIX_PATH with SPIRV-Headers not found" }

  $cmdPath = Join-Path $CacheRoot "build-$editionSlug.cmd"
  $tauriArguments = if ($PackageEdition -eq "Cuda") {
    "build --no-sign --features ort-cuda --config `"$configPath`""
  } else {
    "build --no-sign --config `"$configPath`""
  }
  $lines = @(
    "@echo off",
    "call `"$vcvars`" >nul",
    "if errorlevel 1 exit /b %errorlevel%",
    "set `"VULKAN_SDK=$vulkanSdk`"",
    "set `"PATH=$CacheRoot;$bunDir;$vulkanSdk\Bin;%PATH%`"",
    "set `"CMAKE_PREFIX_PATH=$cmakePrefix`"",
    "set `"ORT_LIB_LOCATION=$($Prepared.ort_lib)`"",
    "set `"ORT_PREFER_DYNAMIC_LINK=1`"",
    "set `"HANDY_VC_REDIST_DIRS=$redist`"",
    "set `"CARGO_TARGET_DIR=$targetDir`"",
    "set `"CARGO=$cargoWrapper`"",
    "set `"CARGO_ENCODED_RUSTFLAGS=$encodedRustFlags`"",
    "set `"CL=$compilerFlags`"",
    "set `"CC_SHELL_ESCAPED_FLAGS=1`"",
    "cd /d `"$repoRoot`"",
    "`"$bun`" run build",
    "if errorlevel 1 exit /b %errorlevel%",
    "`"$bun`" `"$tauriEntrypoint`" $tauriArguments",
    "exit /b %errorlevel%"
  )
  if ($PackageEdition -eq "Cuda") {
    $cudaEnvironment = "set `"HANDY_CUDA_RUNTIME_DIR=$($Prepared.runtime_dir)`""
    $ortPreferenceIndex = [Array]::IndexOf($lines, "set `"ORT_PREFER_DYNAMIC_LINK=1`"")
    $lines = @($lines[0..$ortPreferenceIndex] + $cudaEnvironment + $lines[($ortPreferenceIndex + 1)..($lines.Count - 1)])
  }
  Set-Content -LiteralPath $cmdPath -Value $lines -Encoding ascii
  $bundleRoot = Join-Path $targetDir "release\bundle"
  Reset-OwnedDirectory -Path $bundleRoot -OwnedRoot $CacheRoot
  $buildProcess = Start-Process -FilePath "cmd.exe" `
    -ArgumentList @("/d", "/c", "`"$cmdPath`"") `
    -Wait -PassThru -NoNewWindow
  if ($buildProcess.ExitCode -ne 0) {
    throw "native Windows $PackageEdition build exited $($buildProcess.ExitCode)"
  }

  $nsis = Get-SingleVersionedArtifact (Join-Path $bundleRoot "nsis") $version ".exe" "NSIS"
  $msi = Get-SingleVersionedArtifact (Join-Path $bundleRoot "msi") $version ".msi" "MSI"
  New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
  $nsisOutput = Join-Path $OutputDir $artifactNames.nsis
  $msiOutput = Join-Path $OutputDir $artifactNames.msi
  Copy-Item -LiteralPath $nsis.FullName -Destination $nsisOutput -Force
  Copy-Item -LiteralPath $msi.FullName -Destination $msiOutput -Force

  return [pscustomobject]@{
    nsis = [pscustomobject]@{ path = $nsisOutput; bytes = (Get-Item $nsisOutput).Length; sha256 = Get-Sha256 $nsisOutput }
    msi = [pscustomobject]@{ path = $msiOutput; bytes = (Get-Item $msiOutput).Length; sha256 = Get-Sha256 $msiOutput }
  }
}

function Assert-PackageRoot {
  param(
    [Parameter(Mandatory)][string]$Root,
    [Parameter(Mandatory)][ValidateSet("Cuda", "Cpu")][string]$PackageEdition,
    [Parameter(Mandatory)][string]$ExpectedRuntimeDirectory
  )
  $executable = Get-ChildItem -LiteralPath $Root -Filter $executableName -File -Recurse |
    Select-Object -First 1
  if (-not $executable) { throw "package is missing ${executableName}: $Root" }
  $unexpectedModels = @(Get-UnexpectedModelWeightFiles -Root $Root)
  if ($unexpectedModels.Count -gt 0) {
    throw "package unexpectedly contains model weights: $($unexpectedModels.Name -join ', ')"
  }
  foreach ($license in @("onnxruntime-LICENSE.txt", "onnxruntime-ThirdPartyNotices.txt")) {
    if (-not (Get-ChildItem -LiteralPath $Root -Filter $license -File -Recurse)) {
      throw "$PackageEdition package is missing runtime license $license"
    }
  }
  $dllNames = @(Get-ChildItem -LiteralPath $Root -Filter "*.dll" -File -Recurse | ForEach-Object Name)
  $stagedDlls = @(Get-ChildItem -LiteralPath $ExpectedRuntimeDirectory `
    -Filter "*.dll" -File -ErrorAction SilentlyContinue)
  foreach ($staged in $stagedDlls) {
    if ($staged.Name -notin $dllNames) {
      throw "package is missing staged runtime DLL $($staged.Name)"
    }
  }
  $cudaPatterns = @("onnxruntime_providers_cuda.dll", "cublas*.dll", "cudart*.dll", "cufft*.dll", "cudnn*.dll", "nvrtc*.dll", "nvJitLink*.dll")
  if ($PackageEdition -eq "Cuda") {
    foreach ($required in @("onnxruntime_providers_cuda.dll", "cublas64_13.dll", "cudnn64_9.dll")) {
      if ($required -notin $dllNames) { throw "CUDA package is missing $required" }
    }
    if (-not (Get-ChildItem -LiteralPath $Root -Filter "THIRD_PARTY_NOTICES-CUDA.txt" -File -Recurse)) {
      throw "CUDA package is missing THIRD_PARTY_NOTICES-CUDA.txt"
    }
    foreach ($license in @(
      "cuda_cudart-LICENSE.txt",
      "cuda_nvrtc-LICENSE.txt",
      "libcublas-LICENSE.txt",
      "libcufft-LICENSE.txt",
      "libnvjitlink-LICENSE.txt",
      "cudnn-LICENSE.txt"
    )) {
      if (-not (Get-ChildItem -LiteralPath $Root -Filter $license -File -Recurse)) {
        throw "CUDA package is missing runtime license $license"
      }
    }
  } else {
    foreach ($pattern in $cudaPatterns) {
      if ($dllNames | Where-Object { $_ -like $pattern }) {
        throw "CPU package unexpectedly contains CUDA runtime matching $pattern"
      }
    }
    foreach ($pattern in @(
      "THIRD_PARTY_NOTICES-CUDA.txt",
      "cuda_*",
      "libcublas*",
      "libcufft*",
      "libnvjitlink*",
      "cudnn*"
    )) {
      $metadata = @(Get-ChildItem -LiteralPath $Root -Filter $pattern -File -Recurse)
      if ($metadata.Count -gt 0) {
        throw "CPU package unexpectedly contains NVIDIA metadata $($metadata.Name -join ', ')"
      }
    }
  }
  $closure = Test-PeClosure $Root
  return [pscustomobject]@{
    root = $Root
    edition = $PackageEdition.ToLowerInvariant()
    dll_count = $dllNames.Count
    pe_files = $closure.files
    unresolved_imports = $closure.unresolved
    executable = $executable.FullName
  }
}

function Remove-AuditDirectoryWithRetry {
  param([Parameter(Mandatory)][string]$Path)

  $tempRoot = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath()).TrimEnd(
    [System.IO.Path]::DirectorySeparatorChar
  ) + [System.IO.Path]::DirectorySeparatorChar
  $fullPath = [System.IO.Path]::GetFullPath($Path)
  if (-not $fullPath.StartsWith($tempRoot, [System.StringComparison]::OrdinalIgnoreCase) -or
      (Split-Path -Leaf $fullPath) -notlike "gigatype-audit-*") {
    throw "refusing to remove non-audit temporary directory: $fullPath"
  }

  $lastError = $null
  foreach ($attempt in 1..10) {
    try {
      Remove-Item -LiteralPath $fullPath -Recurse -Force -ErrorAction Stop
      return
    } catch {
      $lastError = $_
      if ($attempt -lt 10) {
        Start-Sleep -Milliseconds 250
      }
    }
  }
  throw "failed to remove audit directory after 10 attempts: $fullPath ($lastError)"
}

function Audit-Installers {
  param(
    [Parameter(Mandatory)][string]$Nsis,
    [Parameter(Mandatory)][string]$Msi,
    [Parameter(Mandatory)][ValidateSet("Cuda", "Cpu")][string]$PackageEdition,
    [Parameter(Mandatory)][string]$ExpectedRuntimeDirectory
  )
  $results = @()
  foreach ($kind in @("nsis", "msi")) {
    $root = Join-Path ([System.IO.Path]::GetTempPath()) ("gigatype-audit-" + [guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Path $root | Out-Null
    try {
      if ($kind -eq "nsis") {
        $process = Start-Process -FilePath $Nsis -ArgumentList @("/S", "/PORTABLE", "/D=$root") -Wait -PassThru
      } else {
        $log = Join-Path $root "msi-admin.log"
        $arguments = "/a `"$Msi`" /qn /L*v `"$log`" TARGETDIR=`"$root`""
        $process = Start-Process -FilePath "msiexec.exe" -ArgumentList $arguments -Wait -PassThru
      }
      if ($process.ExitCode -ne 0) { throw "$kind extraction exited $($process.ExitCode)" }
      $result = Assert-PackageRoot $root $PackageEdition $ExpectedRuntimeDirectory
      $deviceProbe = Start-Process -FilePath $result.executable -ArgumentList "--list-devices" `
        -Wait -PassThru -NoNewWindow
      if ($deviceProbe.ExitCode -ne 0) {
        throw "$kind packaged $executableName --list-devices exited $($deviceProbe.ExitCode)"
      }
      if ($PackageEdition -eq "Cuda") {
        $cudaProbe = Start-Process -FilePath $result.executable `
          -ArgumentList @("--list-accelerators", "--json", "--ort-accelerator", "cuda") `
          -Wait -PassThru -NoNewWindow
        if ($cudaProbe.ExitCode -ne 0) {
          throw "$kind packaged CUDA diagnostics exited $($cudaProbe.ExitCode)"
        }
      }
      $results += $result
    } finally {
      if (Test-Path -LiteralPath $root) { Remove-AuditDirectoryWithRetry $root }
    }
  }
  return $results
}

$prepared = $null
$built = $null
$audit = $null

if ($Mode -in @("Prepare", "Build", "All")) {
  $prepared = if ($Edition -eq "Cuda") {
    Prepare-CudaRuntime
  } else {
    Prepare-CpuRuntime
  }
}
if ($Mode -in @("Build", "All")) {
  $built = Build-WindowsInstallers $prepared $Edition
}
if ($Mode -eq "Audit") {
  if ($PackageRoot) {
    $audit = Assert-PackageRoot `
      ([System.IO.Path]::GetFullPath($PackageRoot)) `
      $Edition `
      $ExpectedStagedRuntimeDir
  } elseif ($Nsis -and $Msi) {
    $audit = Audit-Installers `
      ([System.IO.Path]::GetFullPath($Nsis)) `
      ([System.IO.Path]::GetFullPath($Msi)) `
      $Edition `
      $ExpectedStagedRuntimeDir
  } else {
    throw "Audit mode requires -PackageRoot or both -Nsis and -Msi"
  }
} elseif ($Mode -eq "All") {
  $audit = Audit-Installers $built.nsis.path $built.msi.path $Edition $ExpectedStagedRuntimeDir
}

$result = [ordered]@{
  mode = $Mode.ToLowerInvariant()
  plan = $plan
  prepared = $prepared
  artifacts = $built
  audit = $audit
}
if ($Json) {
  $result | ConvertTo-Json -Depth 10
} else {
  $result
}
