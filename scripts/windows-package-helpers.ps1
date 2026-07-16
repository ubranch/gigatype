function Assert-OwnedPath {
  param(
    [Parameter(Mandatory)][string]$Path,
    [Parameter(Mandatory)][string]$OwnedRoot
  )

  $root = [System.IO.Path]::GetFullPath($OwnedRoot).TrimEnd(
    [System.IO.Path]::DirectorySeparatorChar
  ) + [System.IO.Path]::DirectorySeparatorChar
  $full = [System.IO.Path]::GetFullPath($Path)
  if (-not $full.StartsWith($root, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "refusing to modify path outside owned root: $full"
  }
}

function Reset-OwnedDirectory {
  param(
    [Parameter(Mandatory)][string]$Path,
    [Parameter(Mandatory)][string]$OwnedRoot
  )

  Assert-OwnedPath -Path $Path -OwnedRoot $OwnedRoot
  if (Test-Path -LiteralPath $Path) {
    Remove-Item -LiteralPath $Path -Recurse -Force
  }
  New-Item -ItemType Directory -Path $Path -Force | Out-Null
}

function Get-SingleVersionedArtifact {
  param(
    [Parameter(Mandatory)][string]$Directory,
    [Parameter(Mandatory)][string]$Version,
    [Parameter(Mandatory)][ValidateSet(".exe", ".msi")][string]$Extension,
    [Parameter(Mandatory)][string]$Label
  )

  $artifacts = @(Get-ChildItem -LiteralPath $Directory -Filter "*$Extension" -File -ErrorAction SilentlyContinue)
  $escapedVersion = [regex]::Escape($Version)
  $versionPattern = "(?<![0-9])$escapedVersion(?![0-9])"
  $matching = @($artifacts | Where-Object { $_.BaseName -match $versionPattern })
  if ($artifacts.Count -ne 1 -or $matching.Count -ne 1) {
    $found = if ($artifacts.Count -eq 0) { "none" } else { $artifacts.Name -join ", " }
    throw "$Label bundle output must contain exactly one current-version artifact for $Version; found: $found"
  }
  return $matching[0]
}

function Get-UnexpectedModelWeightFiles {
  param([Parameter(Mandatory)][string]$Root)

  return Get-ChildItem -LiteralPath $Root -File -Recurse | Where-Object {
    $name = $_.Name.ToLowerInvariant()
    # Windows package identity is case-insensitive; only this exact runtime model identity is allowed.
    $name -ne "silero_vad_v4.onnx" -and (
      $name.EndsWith(".onnx.data", [System.StringComparison]::Ordinal) -or
      $_.Extension.ToLowerInvariant() -in @(".bin", ".gguf", ".ggml", ".onnx")
    )
  }
}
