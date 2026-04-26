# HandOff bootstrap installer for Windows (PowerShell 5.1+ / 7+).
#
# Usage:
#   iwr -useb https://raw.githubusercontent.com/NewTurn2017/HandOff/main/bootstrap.ps1 | iex
#   $env:HANDOFF_HOOK=1; iwr -useb https://raw.githubusercontent.com/NewTurn2017/HandOff/main/bootstrap.ps1 | iex
#
# Env vars:
#   HANDOFF_HOME   Install destination. Default: $HOME\.handoff
#   HANDOFF_REPO   Git URL. Default: https://github.com/NewTurn2017/HandOff.git
#   HANDOFF_REF    Branch / tag. Default: main
#   HANDOFF_HOOK   Set to 1 to also register the SessionStart hook in ~/.claude/settings.json
#
# Notes:
#   - Requires git and python3 in PATH.
#   - Symlink creation requires either Developer Mode enabled (Settings → For developers)
#     or running PowerShell as Administrator. Otherwise this script falls back to copying.
#   - The SessionStart hook (load_hook.sh) runs through bash. On Windows, Claude Code's
#     hook runner needs Git Bash or WSL on PATH; otherwise the hook silently no-ops.

$ErrorActionPreference = 'Stop'

$Repo = if ($env:HANDOFF_REPO) { $env:HANDOFF_REPO } else { 'https://github.com/NewTurn2017/HandOff.git' }
$Ref  = if ($env:HANDOFF_REF)  { $env:HANDOFF_REF  } else { 'main' }
$Dest = if ($env:HANDOFF_HOME) { $env:HANDOFF_HOME } else { Join-Path $HOME '.handoff' }
$WantHook = $env:HANDOFF_HOOK -eq '1'

function Need-Cmd($name) {
  if (-not (Get-Command $name -ErrorAction SilentlyContinue)) {
    Write-Host "missing required command: $name" -ForegroundColor Red
    exit 1
  }
}

function Info($msg) { Write-Host $msg -ForegroundColor Cyan }
function Ok($msg)   { Write-Host $msg -ForegroundColor Green }
function Warn($msg) { Write-Host $msg -ForegroundColor Yellow }

Need-Cmd git
Need-Cmd python

# 1. Clone or update
Info "[1/3] cloning $Repo -> $Dest"
if (Test-Path (Join-Path $Dest '.git')) {
  git -C $Dest fetch --quiet origin $Ref
  git -C $Dest checkout --quiet $Ref
  git -C $Dest pull --quiet --ff-only origin $Ref | Out-Null
  Ok "  updated existing checkout."
} else {
  if ((Test-Path $Dest) -and -not (Test-Path (Join-Path $Dest '.git'))) {
    if ((Get-ChildItem -Force $Dest -ErrorAction SilentlyContinue | Measure-Object).Count -gt 0) {
      Write-Host "  $Dest is non-empty and not a git repo. aborting." -ForegroundColor Red
      exit 1
    }
  }
  git clone --quiet --branch $Ref $Repo $Dest
  Ok "  cloned."
}

# 2. Symlink into Claude Code / Codex skill dirs
Info "[2/3] linking skills into ~/.claude/skills and ~/.codex/skills"

$Skills = @('handoff-save', 'handoff-load')
$Targets = @(
  (Join-Path $HOME '.claude\skills'),
  (Join-Path $HOME '.codex\skills')
)

function Try-Symlink($Path, $Target) {
  try {
    New-Item -ItemType SymbolicLink -Path $Path -Target $Target -ErrorAction Stop | Out-Null
    return $true
  } catch {
    return $false
  }
}

$FellBackToCopy = $false
foreach ($dir in $Targets) {
  if (-not (Test-Path $dir)) {
    Write-Host "  skip: $dir does not exist" -ForegroundColor DarkGray
    continue
  }
  foreach ($skill in $Skills) {
    $linkPath = Join-Path $dir $skill
    $srcPath  = Join-Path $Dest "skills\$skill"

    if (Test-Path $linkPath) {
      $item = Get-Item $linkPath -Force
      if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) {
        $existingTarget = (Get-Item $linkPath -Force).Target
        if ($existingTarget -and ($existingTarget | Where-Object { $_ -eq $srcPath })) {
          Write-Host "  ok:   $linkPath (already linked)" -ForegroundColor DarkGray
          continue
        }
      }
      $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
      $backup = "$linkPath.backup-$stamp"
      Write-Host "  move: $linkPath -> $backup"
      Move-Item -Path $linkPath -Destination $backup -Force
    }

    if (Try-Symlink -Path $linkPath -Target $srcPath) {
      Write-Host "  link: $linkPath -> $srcPath" -ForegroundColor Green
    } else {
      Warn "  fallback to copy (symlink permission denied; enable Developer Mode for symlinks)"
      Copy-Item -Recurse -Force -Path $srcPath -Destination $linkPath
      Write-Host "  copy: $linkPath" -ForegroundColor Green
      $FellBackToCopy = $true
    }
  }
}

# 3. Optional hook registration
if ($WantHook) {
  Info "[3/3] registering SessionStart hook"
  python (Join-Path $Dest 'scripts\register_session_hook.py')
} else {
  Info "[3/3] skipping hook registration (set `\$env:HANDOFF_HOOK=1` to enable)"
}

Ok "done. HandOff installed at $Dest"
if ($FellBackToCopy) {
  Warn "Some links fell back to copy mode. To get true symlinks (so 'git pull' updates instantly),"
  Warn "enable Developer Mode (Settings -> For developers) and re-run the installer."
}
Write-Host ""
Write-Host "Next steps:"
Write-Host "  - Start a new Claude Code or Codex session in any project."
Write-Host "  - Try: /handoff-save  or  '핸드오프 저장해줘'"
Write-Host "  - Update later: cd `"$Dest`"; git pull"
