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
#   HANDOFF_HOOK   Set to 1 to also register SessionStart hooks where supported
#
# Notes:
#   - Requires git and python in PATH.
#   - Symlink creation requires either Developer Mode enabled (Settings -> For developers)
#     or running PowerShell as Administrator. Otherwise this script falls back to copying.
#   - SessionStart hooks run load_hook.sh through bash. On Windows, the hook runner needs
#     Git Bash or WSL on PATH; otherwise the hook silently no-ops.

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

# 2. Symlink/copy into supported coding-agent skill dirs
Info "[2/3] linking skills into supported agent skill dirs"

$SkillLinks = @(
  @{ Link = 'handoff-save'; Source = 'handoff-save' },
  @{ Link = 'handoff-load'; Source = 'handoff-load' },
  @{ Link = 'save_handoff_road'; Source = 'handoff-save' },
  @{ Link = 'load_handoff_road'; Source = 'handoff-load' }
)

$Targets = @(
  @{ Name = 'claude'; Dir = if ($env:CLAUDE_SKILLS_DIR) { $env:CLAUDE_SKILLS_DIR } else { Join-Path $HOME '.claude\skills' }; Settings = if ($env:CLAUDE_SETTINGS) { $env:CLAUDE_SETTINGS } else { Join-Path $HOME '.claude\settings.json' } },
  @{ Name = 'codex';  Dir = if ($env:CODEX_SKILLS_DIR)  { $env:CODEX_SKILLS_DIR  } else { Join-Path $HOME '.codex\skills'  }; Settings = '' },
  @{ Name = 'gajae';  Dir = if ($env:GAJAE_SKILLS_DIR)  { $env:GAJAE_SKILLS_DIR  } else { Join-Path $HOME '.gajae\skills'  }; Settings = if ($env:GAJAE_SETTINGS) { $env:GAJAE_SETTINGS } else { Join-Path $HOME '.gajae\settings.json' } },
  @{ Name = 'gjc';    Dir = if ($env:GJC_SKILLS_DIR)    { $env:GJC_SKILLS_DIR    } else { Join-Path $HOME '.gjc\skills'    }; Settings = if ($env:GJC_SETTINGS) { $env:GJC_SETTINGS } else { Join-Path $HOME '.gjc\settings.json' } },
  @{ Name = 'omx';    Dir = if ($env:OMX_SKILLS_DIR)    { $env:OMX_SKILLS_DIR    } else { Join-Path $HOME '.omx\skills'    }; Settings = if ($env:OMX_SETTINGS) { $env:OMX_SETTINGS } else { Join-Path $HOME '.omx\settings.json' } },
  @{ Name = 'wcc';    Dir = if ($env:WCC_SKILLS_DIR)    { $env:WCC_SKILLS_DIR    } else { Join-Path $HOME '.wcc\skills'    }; Settings = if ($env:WCC_SETTINGS) { $env:WCC_SETTINGS } else { Join-Path $HOME '.wcc\settings.json' } }
)

function Try-Symlink($Path, $Target) {
  try {
    New-Item -ItemType SymbolicLink -Path $Path -Target $Target -ErrorAction Stop | Out-Null
    return $true
  } catch {
    return $false
  }
}

function Hook-Cmd($Dir) {
  $normalized = $Dir.Replace('\', '/')
  $homeNormalized = $HOME.Replace('\', '/')
  if ($normalized.StartsWith($homeNormalized)) {
    return ('$HOME' + $normalized.Substring($homeNormalized.Length) + '/handoff-load/scripts/load_hook.sh')
  }
  return ($normalized + '/handoff-load/scripts/load_hook.sh')
}

$FellBackToCopy = $false
foreach ($target in $Targets) {
  $targetName = $target['Name']
  $dir = $target['Dir']
  if (-not (Test-Path $dir)) {
    Write-Host "  skip: $targetName ($dir does not exist)" -ForegroundColor DarkGray
    continue
  }

  foreach ($skill in $SkillLinks) {
    $linkName = $skill['Link']
    $sourceName = $skill['Source']
    $linkPath = Join-Path $dir $linkName
    $srcPath  = Join-Path $Dest (Join-Path 'skills' $sourceName)

    if (Test-Path $linkPath) {
      $item = Get-Item $linkPath -Force
      if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) {
        $existingTarget = (Get-Item $linkPath -Force).Target
        if ($existingTarget -and ($existingTarget | Where-Object { $_ -eq $srcPath })) {
          Write-Host "  ok:   $targetName $linkName (already linked)" -ForegroundColor DarkGray
          continue
        }
      }
      $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
      $backup = "$linkPath.backup-$stamp"
      Write-Host "  move: $linkPath -> $backup"
      Move-Item -Path $linkPath -Destination $backup -Force
    }

    if (Try-Symlink -Path $linkPath -Target $srcPath) {
      Write-Host "  link: $targetName $linkName -> $srcPath" -ForegroundColor Green
    } else {
      Warn "  fallback to copy (symlink permission denied; enable Developer Mode for symlinks)"
      Copy-Item -Recurse -Force -Path $srcPath -Destination $linkPath
      Write-Host "  copy: $targetName $linkName" -ForegroundColor Green
      $FellBackToCopy = $true
    }
  }

  $settings = $target['Settings']
  if ($WantHook -and $settings) {
    $hookCmd = Hook-Cmd $dir
    python (Join-Path $Dest 'scripts\register_session_hook.py') $settings $hookCmd
  }
}

# 3. Finish
if ($WantHook) {
  Info "[3/3] hook registration attempted for supported settings files"
} else {
  Info "[3/3] skipping hook registration (set `$env:HANDOFF_HOOK=1 to enable)"
}

Ok "done. HandOff installed at $Dest"
Ok "canonical handoff storage: `$env:HANDOFF_ROOT or $HOME\.handoff\sessions"
if ($FellBackToCopy) {
  Warn "Some links fell back to copy mode. To get true symlinks (so 'git pull' updates instantly),"
  Warn "enable Developer Mode (Settings -> For developers) and re-run the installer."
}
Write-Host ""
Write-Host "Next steps:"
Write-Host "  - Start a new Claude/Codex/Gajae/OMX/WCC session in any project."
Write-Host "  - Try: /handoff-save, /save_handoff_road, or '핸드오프 저장해줘'"
Write-Host "  - Update later: cd `"$Dest`"; git pull"
