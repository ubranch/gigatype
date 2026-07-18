# Lowercase Repository Surface Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rename the private GitHub repository to `ubranch/gigatype` and make its README prose, description, and topics lowercase without changing released technical contracts.

**Architecture:** Apply one mechanical Markdown transformation that lowercases README text outside fenced code, inline code, and link destinations. Normalize every tracked Markdown canonical repository URL, push documentation before the GitHub rename, then update GitHub metadata and verify the existing release remains byte-for-byte unchanged.

**Tech Stack:** PowerShell 7, Git, GitHub CLI, Markdown

## Global Constraints

- Keep exact released filenames such as `GigaType_0.9.3-gigatype.1_x64-cuda13-setup.exe` unchanged.
- Keep exact executable and command spelling such as `GigaType.exe` unchanged.
- Keep hashes, revisions, version strings, paths, code, and identifiers unchanged.
- Keep release tag `v0.9.3-gigatype.1` and its four published assets unchanged.
- Do not rename application binaries, package identifiers, source symbols, model identifiers, or shipped asset names.
- Preserve private repository visibility and default branch `main`.

---

### Task 1: Lowercase Documentation Surface

**Files:**

- Modify: `README.md`
- Modify: `BUILD.md`
- Modify: `AGENTS.md`
- Modify: `.github/PULL_REQUEST_TEMPLATE.md`
- Modify: `.github/ISSUE_TEMPLATE/bug_report.md`
- Modify: `src/content/release-notes/0.9.0.md`
- Modify: `docs/superpowers/plans/2026-07-16-gigatype-private-fork.md`
- Modify: `docs/superpowers/specs/2026-07-16-gigatype-private-fork-design.md`

**Interfaces:**

- Consumes: approved design in `docs/superpowers/specs/2026-07-17-lowercase-repository-surface-design.md`
- Produces: lowercase README prose plus lowercase canonical repository URLs across tracked Markdown

- [ ] **Step 1: Run the README casing validator and verify it fails**

````powershell
$lines = Get-Content -LiteralPath README.md
$inFence = $false
$violations = foreach ($line in $lines) {
  if ($line -match '^\s*```') { $inFence = -not $inFence; continue }
  if ($inFence) { continue }
  $prose = [regex]::Replace($line, '(`[^`]*`|\]\([^)]+\))', '')
  if ($prose -cmatch '[A-Z]') { $line }
}
if (-not $violations) { throw 'expected uppercase README prose before transformation' }
$violations | Select-Object -First 10
````

Expected: output includes `# GigaType` and other uppercase prose.

- [ ] **Step 2: Lowercase README prose while preserving technical spans**

Run this one-time mechanical rewrite:

````powershell
$path = 'README.md'
$lines = Get-Content -LiteralPath $path
$inFence = $false
$result = foreach ($line in $lines) {
  if ($line -match '^\s*```') {
    $inFence = -not $inFence
    $line
    continue
  }
  if ($inFence) {
    $line
    continue
  }
  $segments = [regex]::Split($line, '(`[^`]*`|\]\([^)]+\))')
  ($segments | ForEach-Object {
    if ($_ -match '^`' -or $_ -match '^\]\(') { $_ } else { $_.ToLowerInvariant() }
  }) -join ''
}
[IO.File]::WriteAllLines(
  (Resolve-Path $path),
  $result,
  [Text.UTF8Encoding]::new($false)
)
````

Use `apply_patch` to normalize every tracked Markdown canonical repository URL to `https://github.com/ubranch/gigatype`, retaining historical prose and branding.

- [ ] **Step 3: Validate lowercase prose and preserved contracts**

````powershell
$lines = Get-Content -LiteralPath README.md
$inFence = $false
$violations = foreach ($line in $lines) {
  if ($line -match '^\s*```') { $inFence = -not $inFence; continue }
  if ($inFence) { continue }
  $prose = [regex]::Replace($line, '(`[^`]*`|\]\([^)]+\))', '')
  if ($prose -cmatch '[A-Z]') { $line }
}
if ($violations) { throw "uppercase README prose remains:`n$($violations -join "`n")" }

$readme = Get-Content -Raw README.md
$required = @(
  'MiB',
  'GiB',
  '220M',
  '600M',
  'GigaType_0.9.3-gigatype.1_x64-setup.exe',
  'GigaType_0.9.3-gigatype.1_x64_en-US.msi',
  'GigaType_0.9.3-gigatype.1_x64-cuda13-setup.exe',
  'GigaType_0.9.3-gigatype.1_x64-cuda13_en-US.msi',
  'GigaType.exe',
  '0.9.3-gigatype.1'
)
foreach ($token in $required) {
  if (-not $readme.Contains($token)) { throw "missing preserved token: $token" }
}
$legacyUrls = git grep -n 'https://github\.com/ubranch/GigaType' -- '*.md'
if ($LASTEXITCODE -eq 0) {
  throw 'uppercase canonical repository URL remains'
}
if ($LASTEXITCODE -ne 1) { throw "canonical URL check failed: $LASTEXITCODE" }
$canonicalUrls = git grep -n 'https://github\.com/ubranch/gigatype' -- '*.md'
if ($LASTEXITCODE -ne 0) { throw "lowercase canonical URL check failed: $LASTEXITCODE" }
git diff --check
````

Expected: no exception; tracked Markdown contains lowercase canonical repository URLs only; `git diff --check` exits `0`.

- [ ] **Step 4: Review and commit documentation**

```powershell
$task1Files = @(
  'README.md',
  'BUILD.md',
  'AGENTS.md',
  '.github/PULL_REQUEST_TEMPLATE.md',
  '.github/ISSUE_TEMPLATE/bug_report.md',
  'src/content/release-notes/0.9.0.md',
  'docs/superpowers/plans/2026-07-16-gigatype-private-fork.md',
  'docs/superpowers/specs/2026-07-16-gigatype-private-fork-design.md'
)
git diff -- $task1Files
git add -- $task1Files
$staged = @(git diff --cached --name-only | Sort-Object)
$expected = @($task1Files | Sort-Object)
if (Compare-Object -ReferenceObject $expected -DifferenceObject $staged) {
  throw 'staged file list differs from the Task 1 allowlist'
}
git diff --cached --check
git commit -m "docs: lowercase repository surface"
```

Expected: commit contains only the eight Task 1 files in `$task1Files`.

---

### Task 2: Rename Repository and Update Metadata

**Files:**

- Modify local Git remote config: `private`
- Modify GitHub repository metadata: `ubranch/GigaType`

**Interfaces:**

- Consumes: committed documentation from Task 1
- Produces: `ubranch/gigatype` with lowercase description/topics and updated local remote

- [ ] **Step 1: Push committed documentation to private `main`**

```powershell
git status --short
git push private HEAD:main
```

Expected: empty status before push; private `main` advances to local `HEAD`.

- [ ] **Step 2: Rename the GitHub repository**

```powershell
gh repo rename -R ubranch/GigaType gigatype --yes
```

Expected: repository becomes `ubranch/gigatype`; visibility remains private.

- [ ] **Step 3: Set lowercase description and topics**

```powershell
gh repo edit ubranch/gigatype `
  --description 'private gigatype fork with gigaam multilingual and windows cuda support' `
  --add-topic speech-to-text `
  --add-topic windows `
  --add-topic cuda `
  --add-topic gigaam `
  --add-topic tauri `
  --add-topic rust
```

Expected: description equals supplied lowercase string; topics equal the six lowercase values.

- [ ] **Step 4: Update local private remote**

```powershell
git remote set-url private git@github.com:ubranch/gigatype.git
git remote get-url private
```

Expected: `git@github.com:ubranch/gigatype.git`.

---

### Task 3: Verify Repository and Release Integrity

**Files:**

- Verify only; no file changes

**Interfaces:**

- Consumes: renamed repository and existing release `v0.9.3-gigatype.1`
- Produces: current proof for metadata, branch, tag, assets, and worktree

- [ ] **Step 1: Verify repository metadata**

```powershell
$repo = gh repo view ubranch/gigatype --json nameWithOwner,description,isPrivate,defaultBranchRef,repositoryTopics,url | ConvertFrom-Json
$expectedTopics = @('cuda', 'gigaam', 'rust', 'speech-to-text', 'tauri', 'windows')
$actualTopics = @($repo.repositoryTopics.name | Sort-Object)
if ($repo.nameWithOwner -ne 'ubranch/gigatype') { throw "wrong repository: $($repo.nameWithOwner)" }
if ($repo.description -ne 'private gigatype fork with gigaam multilingual and windows cuda support') { throw 'wrong description' }
if (-not $repo.isPrivate -or $repo.defaultBranchRef.name -ne 'main') { throw 'visibility or default branch changed' }
if (($actualTopics -join ',') -ne ($expectedTopics -join ',')) { throw "wrong topics: $($actualTopics -join ',')" }
$repo | ConvertTo-Json -Depth 5
```

Expected: no exception; URL is `https://github.com/ubranch/gigatype`.

- [ ] **Step 2: Verify default branch, release tag, and four asset digests**

```powershell
$expectedDigests = @{
  'GigaType_0.9.3-gigatype.1_x64-setup.exe' = 'sha256:cb47bdc4bb866a5b5de9a37d1c8af45360fe50419fadb3d4370eb44529678ea0'
  'GigaType_0.9.3-gigatype.1_x64_en-US.msi' = 'sha256:f0629a60f73826b16493d42410fd03eb99c277b2fac0124d5186aabf1fe70583'
  'GigaType_0.9.3-gigatype.1_x64-cuda13-setup.exe' = 'sha256:e229fcb93e69adca3d1acf79970d052e3002d8ff230f42b0322e94af54a1b588'
  'GigaType_0.9.3-gigatype.1_x64-cuda13_en-US.msi' = 'sha256:261fc91c6e5764f23f3693a7402c80cabb94bce7c7d96620083fe5384b3fbc78'
}
$release = gh release view v0.9.3-gigatype.1 --repo ubranch/gigatype --json tagName,isDraft,isPrerelease,assets,url | ConvertFrom-Json
if ($release.isDraft -or $release.isPrerelease -or $release.assets.Count -ne 4) { throw 'release state changed' }
foreach ($asset in $release.assets) {
  if ($asset.state -ne 'uploaded' -or $expectedDigests[$asset.name] -ne $asset.digest) {
    throw "release asset changed: $($asset.name)"
  }
}
$tag = (git ls-remote private refs/tags/v0.9.3-gigatype.1).Split()[0]
if ($tag -ne '6c315fe4c76cad32b156d9fab992bef34124c7f0') { throw "release tag moved: $tag" }
$main = (git ls-remote private refs/heads/main).Split()[0]
$head = git rev-parse HEAD
if ($main -ne $head) { throw "private main mismatch: remote=$main local=$head" }
```

Expected: no exception; release tag remains on `6c315fe4c76cad32b156d9fab992bef34124c7f0`; private `main` equals local `HEAD`.

- [ ] **Step 3: Final worktree check**

```powershell
git status --short
git diff --check
```

Expected: no output; both commands exit `0`.
