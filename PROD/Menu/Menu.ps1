# WinPE Script Menu (ASCII-only, PS5/WinPE-safe)
# Tools go in: X:\Windows\System32\Tools
# Optional description: first line of each script
#   PowerShell:  # DESC: My tool
#   Batch:       :: DESC: My tool

$ErrorActionPreference = 'Stop'
$ToolsDir = 'X:\Windows\System32\Tools'
$LogPath  = 'X:\menu.log'

function Write-Log($msg) {
  $ts = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
  "$ts  $msg" | Tee-Object -FilePath $LogPath -Append | Out-Host
}

function Get-Desc($path) {
  try {
    $first = Get-Content -LiteralPath $path -Encoding UTF8 -TotalCount 1
    if ($first -match '^\s*(#|::)\s*DESC:\s*(.+)$') { return $Matches[2].Trim() }
  } catch {}
  return ''
}

function Discover-Tools {
  if (-not (Test-Path $ToolsDir)) { New-Item -ItemType Directory -Path $ToolsDir | Out-Null }
  $items = @()

  $scripts = Get-ChildItem -LiteralPath $ToolsDir -Recurse -File -Include *.ps1,*.cmd,*.bat -ErrorAction SilentlyContinue
  foreach ($s in $scripts) {
    $items += [pscustomobject]@{
      Name = $s.BaseName
      Path = $s.FullName
      Ext  = $s.Extension.ToLower()
      Desc = Get-Desc $s.FullName
    }
  }

  $builtins = @(
    [pscustomobject]@{ Name='Open CMD';                Path='builtin-cmd'; Ext='.builtin'; Desc='Open command prompt' },
    [pscustomobject]@{ Name='DiskPart';                Path='builtin-dp';  Ext='.builtin'; Desc='Quick disk view'    },
  #  [pscustomobject]@{ Name='IP tools';                Path='builtin-ip';  Ext='.builtin'; Desc='ipconfig/ping/etc'  },
    [pscustomobject]@{ Name='Reboot';                  Path='wpeutil reboot';   Ext='.run'; Desc='Restart'          },
    [pscustomobject]@{ Name='Shutdown';                Path='wpeutil shutdown'; Ext='.run'; Desc='Power off'        }
  #  [pscustomobject]@{ Name='Bootrec Repair';          Path='builtin-bootrec'; Ext='.builtin'; Desc='Fix MBR, Boot, BCD' },
  #  [pscustomobject]@{ Name='BCD Rebuild';             Path='builtin-bcdboot'; Ext='.builtin'; Desc='Rebuild BCD store' },
  #  [pscustomobject]@{ Name='Offline SFC';             Path='builtin-sfc'; Ext='.builtin'; Desc='Scan OS files offline' }
  )
  return ($items + $builtins)
}

function Normalize-Drive {
  param([string]$Value)
  if ([string]::IsNullOrWhiteSpace($Value)) { return $null }
  $clean = $Value.Trim()
  $clean = $clean.TrimEnd('\')
  if ($clean.Length -eq 1) { $clean = $clean + ':' }
  return $clean.ToUpper()
}

function Get-OfflineWindowsDrive {
  foreach ($letter in 'C','D','E','F','G','H','I','J','K','L','M','N','O','P','Q','R','S','T','U','V','W','X','Y','Z') {
    $systemHive = "{0}:\Windows\System32\Config\SYSTEM" -f $letter
    if (Test-Path -LiteralPath $systemHive) { return ("{0}:" -f $letter) }
  }
  return $null
}

function Get-DefaultEfiPartition {
  foreach ($letter in 'C','D','E','F','G','H','I','J','K','L','M','N','O','P','Q','R','S','T','U','V','W','X','Y','Z') {
    $efiPath = "{0}:\EFI" -f $letter
    if (Test-Path -LiteralPath $efiPath) { return ("{0}:" -f $letter) }
  }
  return $null
}

function Run-Item($item) {
  Clear-Host
  Write-Host ("=== Running: {0}`n" -f $item.Name) -ForegroundColor Cyan
  Write-Log ("RUN {0}" -f $item.Path)

  $pushed = $false
  $toolPath = $item.Path
  $toolDir  = $null
  if ($toolPath -and (Test-Path -LiteralPath $toolPath)) {
    try { $toolDir = [System.IO.Path]::GetDirectoryName($toolPath) } catch {}
    if ($toolDir -and (Test-Path -LiteralPath $toolDir)) {
      Push-Location -LiteralPath $toolDir
      $pushed = $true
    }
  }

  try {
    switch -Regex ($item.Ext) {
      '\.ps1$' {
        Start-Process -FilePath powershell.exe -ArgumentList '-NoLogo','-NoProfile','-ExecutionPolicy','Bypass','-File',$item.Path -Wait -NoNewWindow
      }
      '\.(cmd|bat)$' {
        & $item.Path
      }
      '\.run$' {
        Start-Process -FilePath cmd.exe -ArgumentList '/c', $item.Path -NoNewWindow -Wait
      }
      '\.exe$' {
        & $item.Path
      }
      default {
        switch ($item.Path) {
          'builtin-cmd' { & cmd }
          'builtin-dp'  {
            $tmp = [System.IO.Path]::GetTempFileName()
            Set-Content -LiteralPath $tmp -Value "list disk`r`nlist volume`r`nexit" -Encoding ASCII
            & diskpart /s $tmp
            Remove-Item -LiteralPath $tmp -Force
          }
          'builtin-ip'  {
            ipconfig /all
            Write-Host ""
            Write-Host "Examples:" -ForegroundColor DarkGray
            Write-Host "  net use Z: \\server\share" -ForegroundColor DarkGray
            Write-Host "  ping 8.8.8.8" -ForegroundColor DarkGray
          }
          'builtin-bootrec' {
            bootrec /fixmbr
            bootrec /fixboot
            bootrec /scanos
            bootrec /rebuildbcd
          }
          'builtin-bcdboot' {
            $defaultWinDrive = Get-OfflineWindowsDrive
            $defaultWinDir = if ($defaultWinDrive) { Join-Path $defaultWinDrive 'Windows' } else { 'C:\Windows' }
            $win = Read-Host ("Enter Windows directory (default {0})" -f $defaultWinDir)
            if (-not $win) { $win = $defaultWinDir }

            $defaultEsp = Get-DefaultEfiPartition
            $espPrompt = if ($defaultEsp) { "Enter EFI partition letter (default $defaultEsp)" } else { "Enter EFI partition letter (e.g. S:)" }
            $esp = Read-Host $espPrompt
            if (-not $esp) { $esp = $defaultEsp }
            $esp = Normalize-Drive $esp
            if (-not $esp) {
              Write-Host "EFI partition letter is required." -ForegroundColor Red
              break
            }

            bcdboot $win /s $esp /f UEFI
          }
          'builtin-sfc' {
            $defaultWinDrive = Get-OfflineWindowsDrive
            $prompt = if ($defaultWinDrive) { "Target Windows drive (default $defaultWinDrive)" } else { "Target Windows drive (e.g. C:)" }
            $drive = Read-Host $prompt
            if (-not $drive) { $drive = $defaultWinDrive }
            $drive = Normalize-Drive $drive
            if (-not $drive) {
              Write-Host "Windows drive is required." -ForegroundColor Red
              break
            }

            $offboot = $drive + '\'
            $offwin  = Join-Path $drive 'Windows'
            sfc /scannow /offbootdir=$offboot /offwindir=$offwin
          }
          default {
            if ($item.Path) { & $item.Path }
          }
        }
      }
    }
  }
  finally {
    if ($pushed) { Pop-Location }
  }

  Write-Host ""
  Write-Host "Press ENTER to return to menu..." -ForegroundColor DarkGray
  [void][System.Console]::ReadLine()
}

function Show-Menu {
  while ($true) {
    Clear-Host
    Write-Host "WINPE TOOL MENU" -ForegroundColor Green
    Write-Host ("Tools folder: {0}" -f $ToolsDir)
    Write-Host ""

    $items = Discover-Tools | Sort-Object Name
    if (-not $items -or $items.Count -eq 0) {
      Write-Host "No tools found. Drop .ps1/.cmd/.bat files in the Tools folder." -ForegroundColor Yellow
    }

    $i = 1
    foreach ($t in $items) {
      $label = $t.Name
      if ($t.Desc -and $t.Desc.Trim().Length -gt 0) { $label = $label + " - " + $t.Desc }
      "{0,2}) {1}" -f $i, $label | Out-Host
      $i++
    }
    if ($items) { "" | Out-Host }

    $choice = Read-Host "Select a number (R=refresh, Q=quit)"
    if ($choice -match '^[Qq]$') { break }
    if ($choice -match '^[Rr]$') { continue }
    if ($choice -notmatch '^\d+$') { continue }

    $idx = [int]$choice
    if ($idx -lt 1 -or $idx -gt $items.Count) { continue }
    Run-Item $items[$idx-1]
  }
}

# widen console (best effort)
try { (Get-Host).UI.RawUI.WindowSize = New-Object Management.Automation.Host.Size 120, 40 } catch {}
Show-Menu
