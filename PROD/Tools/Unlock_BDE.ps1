# DESC: Unlock BitLocker volumes Using Recovery Key file.

$ErrorActionPreference = 'Stop'

function Pause-Return {
  Write-Host ""
  Write-Host "Press ENTER to return..." -ForegroundColor DarkGray
  [void][Console]::ReadLine()
}

function Normalize-DrivePath([string]$value) {
  if ([string]::IsNullOrWhiteSpace($value)) { return $null }
  $trimmed = $value.Trim()
  if ($trimmed.Length -eq 1 -and $trimmed -match '^[A-Za-z]$') { return ($trimmed.ToUpper() + ':') }
  if ($trimmed -match '^[A-Za-z]:$') { return $trimmed.ToUpper() }
  if ($trimmed -match '^[A-Za-z]:\\$') { return $trimmed.Substring(0,2).ToUpper() }
  return $trimmed
}

function Ensure-VolumeGuidLetter {
  param(
    [string]$VolumeId,
    [string]$Label,
    [string[]]$PreferredLetters = @('S','T','U','V','W','Y','Z','R','Q','P')
  )

  if ([string]::IsNullOrWhiteSpace($VolumeId)) { return $null }
  $id = $VolumeId.Trim()
  if (-not $id.EndsWith('\')) { $id += '\' }

  $used = @(Get-PSDrive -PSProvider FileSystem | ForEach-Object { $_.Name.Trim().ToUpper() })
  $candidates = @()
  if ($PreferredLetters) { $candidates += $PreferredLetters }
  $candidates += @('D','E','F','G','H','I','J','K','L','M','N','O','P','Q','R','S','T','U','V','W','Y','Z')
  $candidates = $candidates | Select-Object -Unique

  foreach ($letter in $candidates) {
    if ($used -contains $letter) { continue }
    $cmd = "mountvol {0}: {1}" -f $letter, $id
    $null = cmd /c $cmd 2>$null
    if ($LASTEXITCODE -eq 0 -and (Test-Path ("{0}:\\" -f $letter))) {
      $labelDisplay = if ($Label) { " ($Label)" } else { '' }
      Write-Host "Assigned $letter`: to BitLocker volume $VolumeId$labelDisplay" -ForegroundColor DarkGray
      return ($letter + ':')
    }
  }

  return $null
}

function Get-BitLockerVolumes {
  $raw = & manage-bde -status 2>$null
  $volumes = @()
  $current = $null
  $captureMounts = $false

  foreach ($line in $raw) {
    if ($line -match '^\s*Volume\s+(.+)$') {
      if ($current) { $volumes += [pscustomobject]$current }
      $captureMounts = $false
      $rawVol = $Matches[1].Trim()
      $volumeId = $rawVol
      $label = ''
      $mountPoint = ''
      if ($rawVol -match '^([A-Z]):\s*(\[(.+?)\])?') {
        $volumeId = ($Matches[1] + ':')
        if ($Matches[3]) { $label = $Matches[3] }
        $mountPoint = $volumeId
      } elseif ($rawVol -match '^(\\\\\?\\Volume\{[^\}]+\}\\)\s*(\[(.+?)\])?') {
        $volumeId = $Matches[1]
        if ($Matches[3]) { $label = $Matches[3] }
      }
      $current = @{
        VolumeId = $volumeId
        Label = $label
        MountPoint = $mountPoint
        MountPoints = @()
        LockStatus = ''
        ProtectionStatus = ''
        ConversionStatus = ''
        PercentageEncrypted = ''
      }
      continue
    }

    if (-not $current) { continue }

    if ($line -match 'Mount Point\(s\):\s*(.*)$') {
      $captureMounts = $true
      $points = $Matches[1].Trim()
      $current.MountPoints = @()
      if ($points) {
        foreach ($p in $points.Split(' ',[System.StringSplitOptions]::RemoveEmptyEntries)) {
          $mount = $p.Trim().TrimEnd('\\')
          if ($mount) { $current.MountPoints += $mount }
        }
      }
      if ($current.MountPoints.Count -gt 0 -and -not $current.MountPoint) {
        $current.MountPoint = $current.MountPoints[0]
      }
      continue
    }

    if ($captureMounts -and ($line -match '^\s{6,}(.+)$')) {
      $extra = $Matches[1].Trim()
      if ($extra) {
        $mount = $extra.Trim().TrimEnd('\\')
        if ($mount) { $current.MountPoints += $mount }
        if (-not $current.MountPoint) { $current.MountPoint = $mount }
      }
      continue
    } else {
      $captureMounts = $false
    }

    if ($line -match 'Lock Status:\s*(.+)$') { $current.LockStatus = $Matches[1].Trim(); continue }
    if ($line -match 'Protection Status:\s*(.+)$') { $current.ProtectionStatus = $Matches[1].Trim(); continue }
    if ($line -match 'Conversion Status:\s*(.+)$') { $current.ConversionStatus = $Matches[1].Trim(); continue }
    if ($line -match 'Percentage Encrypted:\s*(.+)$') { $current.PercentageEncrypted = $Matches[1].Trim(); continue }
  }

  if ($current) { $volumes += [pscustomobject]$current }
  return $volumes
}

function Get-LockedVolumes {
  $status = Get-BitLockerVolumes
  $locked = @()
  foreach ($vol in $status) {
    if ($vol.LockStatus -and $vol.LockStatus -match 'Locked') {
      $path = Normalize-DrivePath $vol.MountPoint
      if (-not $path) {
        $path = Ensure-VolumeGuidLetter -VolumeId $vol.VolumeId -Label $vol.Label
      }
      if (-not $path) {
        $path = $vol.VolumeId.TrimEnd('\\')
      }
      $display = if ($path -and $path -match '^[A-Z]:$') { $path } else { $vol.VolumeId }
      $locked += [pscustomobject]@{
        Path = $path
        Display = $display
        Label = $vol.Label
        VolumeId = $vol.VolumeId
      }
    }
  }
  return $locked
}

function Pick-LockedVolume([string]$prompt) {
  $locked = Get-LockedVolumes
  if (-not $locked -or $locked.Count -eq 0) {
    $ans = Read-Host "$prompt"
    return (Normalize-DrivePath $ans)
  }

  Write-Host ""
  Write-Host "Locked BitLocker volumes:" -ForegroundColor Yellow
  $idx = 0
  foreach ($vol in $locked) {
    $idx++
    $label = if ($vol.Label) { $vol.Label } else { '' }
    "{0,2}) {1,-24} Label={2}" -f $idx, $vol.Display, $label | Write-Host
  }

  $default = $locked | Where-Object { $_.Label -and $_.Label.ToUpper().Contains('DATA') } | Select-Object -First 1
  if (-not $default) { $default = $locked[0] }
  $defaultDisplay = if ($default.Path) { $default.Path } else { $default.Display }

  $ans = Read-Host ("{0} (default {1})" -f $prompt, $defaultDisplay)
  if ([string]::IsNullOrWhiteSpace($ans)) { return $default.Path }
  if ($ans -match '^\d+$') {
    $choice = [int]$ans
    if ($choice -ge 1 -and $choice -le $locked.Count) { return $locked[$choice-1].Path }
    return $null
  }
  return (Normalize-DrivePath $ans)
}

function Show-Status([string]$d) {
  if (-not $d) { $d = Pick-LockedVolume "Drive or volume to show" }
  if (-not $d) { return }
  & manage-bde -status $d
}

function Unlock-ByPassword([string]$d) {
  if (-not $d) { $d = Pick-LockedVolume "Drive to unlock by password" }
  if (-not $d) { return }
  Write-Host "A password prompt will appear in the console. Type the BitLocker password and press ENTER." -ForegroundColor Yellow
  & manage-bde -unlock $d -password
  & manage-bde -status $d
}

function Unlock-ByRecovery([string]$d) {
  if (-not $d) { $d = Pick-LockedVolume "Drive to unlock by recovery key" }
  if (-not $d) { return }
  $rp = Read-Host "Paste 48-digit recovery password (with dashes)"
  if (-not $rp) { return }
  & manage-bde -unlock $d -recoverypassword $rp
  & manage-bde -status $d
}

function Extract-48Key([string]$text) {
  if (-not $text) { return $null }
  $digits = ($text -replace '\D','')
  if ($digits.Length -ge 48) {
    $digits = $digits.Substring(0,48)
    $groups = for ($i=0; $i -lt 48; $i+=6) { $digits.Substring($i,6) }
    return ($groups -join '-')
  }
  $m = [regex]::Match($text, '(\d{6}-){7}\d{6}')
  if ($m.Success) { return $m.Value }
  return $null
}


function Get-DiskpartVolumes {
  $tmp = [System.IO.Path]::GetTempFileName()
  Set-Content -LiteralPath $tmp -Value "list volume" -Encoding ASCII
  $raw = cmd /c "diskpart /s `"$tmp`"" 2>$null
  Remove-Item -Force $tmp -ErrorAction SilentlyContinue

  $rows = @()
  foreach ($line in $raw) {
    if ($line -match '^\s*Volume\s+\d+') {
      $parts = ($line -replace '\s{2,}', '|').Trim('|').Split('|')
      $volText = $parts[0].Trim()
      $num = $null
      if ($volText -match 'Volume\s+(\d+)') { $num = [int]$Matches[1] }
      $rows += [pscustomobject]@{
        Number = $num
        Volume = $volText
        Ltr    = if ($parts.Count -gt 1) { $parts[1].Trim() } else { '' }
        Label  = if ($parts.Count -gt 2) { $parts[2].Trim() } else { '' }
        Fs     = if ($parts.Count -gt 3) { $parts[3].Trim() } else { '' }
        Type   = if ($parts.Count -gt 4) { $parts[4].Trim() } else { '' }
        Size   = if ($parts.Count -gt 5) { $parts[5].Trim() } else { '' }
        Status = if ($parts.Count -gt 6) { $parts[6].Trim() } else { '' }
        Info   = if ($parts.Count -gt 7) { $parts[7].Trim() } else { '' }
      }
    }
  }
  return $rows
}

function Ensure-DiskpartVolumeLetter {
  param(
    [pscustomobject]$Volume,
    [string[]]$PreferredLetters = @('S','T','U','V','W','Y','Z','R','Q','P')
  )

  if (-not $Volume) { return $null }

  $normalize = {
    param($value)
    if ([string]::IsNullOrWhiteSpace($value)) { return '' }
    return $value.Trim().TrimEnd(':','\').ToUpper()
  }

  $existing = & $normalize $Volume.Ltr
  if ($existing) { return ($existing + ':') }

  $number = $null
  if ($Volume.Number) { $number = [int]$Volume.Number }
  elseif ($Volume.Volume -match 'Volume\s+(\d+)') { $number = [int]$Matches[1] }

  if (-not $number) { return $null }

  $used = @(Get-PSDrive -PSProvider FileSystem | ForEach-Object { $_.Name.Trim().ToUpper() })
  $candidates = @()
  if ($PreferredLetters) { $candidates += $PreferredLetters }
  $candidates += @('D','E','F','G','H','I','J','K','L','M','N','O','P','Q','R','S','T','U','V','W','Y','Z')
  $candidates = $candidates | Select-Object -Unique

  foreach ($letter in $candidates) {
    if ($used -contains $letter) { continue }
    $tmp = [System.IO.Path]::GetTempFileName()
    $script = "select volume $number`nassign letter=$letter"
    Set-Content -LiteralPath $tmp -Value $script -Encoding ASCII
    $null = cmd /c "diskpart /s `"$tmp`"" 2>$null
    Remove-Item -Force $tmp -ErrorAction SilentlyContinue
    Start-Sleep -Milliseconds 300
    $updated = Get-DiskpartVolumes | Where-Object { $_.Number -eq $number } | Select-Object -First 1
    $newLetter = if ($updated) { & $normalize $updated.Ltr } else { '' }
    if ($newLetter) { return ($newLetter + ':') }
  }

  return $null
}

function Pick-DataVolume {
  param(
    [string]$PreferLabel = 'data'
  )

  $vols = Get-DiskpartVolumes | Where-Object { $_.Type -in 'Partition','Removable','CD-ROM' }
  if (-not $vols) { return $null }

  $normalizeLabel = {
    param($value)
    if ([string]::IsNullOrWhiteSpace($value)) { return '' }
    return $value.Trim().ToUpper()
  }
  $target = & $normalizeLabel $PreferLabel

  $assigned = $false
  if ($target) {
    foreach ($vol in $vols | Where-Object { (& $normalizeLabel $_.Label) -eq $target }) {
      if (-not (& $normalizeLabel $vol.Ltr)) {
        if (Ensure-DiskpartVolumeLetter -Volume $vol) { $assigned = $true }
      }
    }
    if ($assigned) {
      $vols = Get-DiskpartVolumes | Where-Object { $_.Type -in 'Partition','Removable','CD-ROM' }
    }
  }

  Write-Host "`n== Available volumes ==" -ForegroundColor Cyan
  $index = 0
  foreach ($vol in $vols) {
    $index++
    $labelNorm = & $normalizeLabel $vol.Label
    $mark = ' '
    if ($target) {
      if ($labelNorm -eq $target) { $mark = '*' }
      elseif ($labelNorm -like "*$target*") { $mark = '~' }
    }
    $ltr = if ($vol.Ltr) { $vol.Ltr.Trim() } else { '--' }
    "{0,2}) {1}  Ltr={2,-2}  Label={3,-16}  Fs={4,-6}  Size={5}" -f $index,$mark,$ltr,$vol.Label,$vol.Fs,$vol.Size | Write-Host
  }
  if ($target) {
    Write-Host "   * = label matches '$PreferLabel'" -ForegroundColor DarkGray
    Write-Host "   ~ = label contains '$PreferLabel'" -ForegroundColor DarkGray
  }

  $defaultVolume = $vols | Where-Object { (& $normalizeLabel $_.Label) -eq $target } | Select-Object -First 1
  if (-not $defaultVolume -and $target) {
    $defaultVolume = $vols | Where-Object { (& $normalizeLabel $_.Label) -like "*$target*" } | Select-Object -First 1
  }
  if (-not $defaultVolume) {
    $defaultVolume = $vols | Where-Object { $_.Ltr } | Select-Object -First 1
  }
  if (-not $defaultVolume -and $vols.Count -gt 0) {
    $defaultVolume = $vols[0]
  }

  $defaultLetter = if ($defaultVolume -and $defaultVolume.Ltr) { $defaultVolume.Ltr.Trim().ToUpper() } else { '' }
  $prompt = "Pick item # or type drive letter for the DATA volume"
  if ($defaultLetter) { $prompt += " (default {0}:)" -f $defaultLetter } else { $prompt += ':' }

  $answer = Read-Host $prompt
  if ([string]::IsNullOrWhiteSpace($answer)) {
    if ($defaultVolume) { return Ensure-DiskpartVolumeLetter -Volume $defaultVolume }
    return $null
  }

  if ($answer -match '^\d+$') {
    $idx = [int]$answer
    if ($idx -ge 1 -and $idx -le $vols.Count) {
      return Ensure-DiskpartVolumeLetter -Volume $vols[$idx-1]
    }
    return $null
  } else {
    $ltr = $answer.Trim().TrimEnd(':','\').ToUpper()
    if ($ltr.Length -eq 1) { return ($ltr + ':') }
    return $null
  }
}

function Select-RecoveryKeyFile {
  $dataDrive = Pick-DataVolume
  if (-not $dataDrive) { return $null }

  $root = $dataDrive
  if (-not $root.EndsWith(':')) { $root = Normalize-DrivePath $root }
  if (-not $root) { return $null }
  $rootWithSep = $root + '\'

  $search = @()
  $search += Get-ChildItem -LiteralPath $rootWithSep -Filter *.txt -File -ErrorAction SilentlyContinue
  $search += Get-ChildItem -LiteralPath (Join-Path $rootWithSep 'Recovery') -Filter *.txt -File -Recurse -ErrorAction SilentlyContinue
  $search += Get-ChildItem -LiteralPath $rootWithSep -Filter *.bek -File -ErrorAction SilentlyContinue
  $files = $search | Sort-Object FullName | Select-Object -Unique

  if (-not $files -or $files.Count -eq 0) {
    Write-Host "No obvious recovery key files found on $root." -ForegroundColor Yellow
    $manual = Read-Host "Enter full path to recovery file (ENTER to cancel)"
    if ([string]::IsNullOrWhiteSpace($manual)) { return $null }
    $manual = $manual.Trim()
    if ($manual -notmatch '^[A-Za-z]:') { $manual = Join-Path $rootWithSep $manual }
    return $manual
  }

  Write-Host "Recovery key candidates:" -ForegroundColor Yellow
  $i = 0
  foreach ($file in $files) {
    $i++
    "{0,2}) {1}" -f $i, $file.FullName | Write-Host
    if ($i -ge 20) { break }
  }
  if ($files.Count -gt 20) { Write-Host "...and more" -ForegroundColor DarkGray }

  $choice = Read-Host "Select item # or type path (ENTER to cancel)"
  if ([string]::IsNullOrWhiteSpace($choice)) { return $null }
  if ($choice -match '^\d+$') {
    $idx = [int]$choice
    if ($idx -ge 1 -and $idx -le $files.Count) { return $files[$idx-1].FullName }
    Write-Host "Invalid selection." -ForegroundColor Red
    return $null
  }
  $path = $choice.Trim()
  if ($path -notmatch '^[A-Za-z]:') { $path = Join-Path $rootWithSep $path }
  return $path
}

function Unlock-ByRecoveryFile([string]$d) {
  if (-not $d) { $d = Pick-LockedVolume "Drive to unlock by recovery file" }
  if (-not $d) { return }

  $keyPath = Select-RecoveryKeyFile
  if (-not $keyPath) { return }
  if (-not (Test-Path -LiteralPath $keyPath)) {
    Write-Host "File not found: $keyPath" -ForegroundColor Red
    return
  }

  try {
    $content = Get-Content -LiteralPath $keyPath -Raw -ErrorAction Stop
  } catch {
    Write-Host "Failed to read $keyPath" -ForegroundColor Red
    return
  }

  $key = Extract-48Key $content
  if (-not $key) {
    Write-Host "No 48-digit recovery key found in $keyPath" -ForegroundColor Red
    return
  }

  Write-Host "`n> manage-bde -unlock $d -rp $key" -ForegroundColor Yellow
  cmd /c "manage-bde -unlock $d -rp $key"

  Write-Host ""
  try { manage-bde -status $d } catch {}
}


function Enable-AutoUnlock([string]$d) {
  if (-not $d) { $d = Pick-LockedVolume "Drive to enable auto-unlock" }
  if (-not $d) { return }
  & manage-bde -autounlock -enable $d
  & manage-bde -status $d
}

function Lock-Volume([string]$d) {
  if (-not $d) { $d = Pick-LockedVolume "Drive to lock" }
  if (-not $d) { return }
  & manage-bde -lock $d
  & manage-bde -status $d
}

# --- Simple menu ---
while ($true) {
  Clear-Host
  Write-Host "BITLOCKER UNLOCK TOOL" -ForegroundColor Green
  Write-Host ""
  Write-Host " 1) Scan and list locked volumes"
  Write-Host " 2) Unlock with recovery key file"
  Write-Host " 3) Unlock with recovery key (manual entry)"
  Write-Host " 4) Show BDE status for a volume"
  Write-Host " 5) Lock a volume"
  Write-Host " Q) Quit"
  Write-Host ""
  $c = Read-Host "Choose"
  $choice = if ($c) { $c.Trim().ToUpper() } else { '' }
  switch ($choice) {
    '1' {
      $locked = Get-LockedVolumes
      if ($locked -and $locked.Count -gt 0) {
        Write-Host "Locked volumes:" -ForegroundColor Yellow
        foreach ($vol in $locked) {
          $label = if ($vol.Label) { $vol.Label } else { '' }
          Write-Host "  $($vol.Display)  Label=$label"
        }
      } else {
        Write-Host "No locked volumes found." -ForegroundColor Yellow
      }
      Pause-Return
    }
    '2' { Unlock-ByRecoveryFile $null; Pause-Return }
    '3' { Unlock-ByRecovery $null; Pause-Return }
    '4' { Show-Status $null; Pause-Return }
    '5' { Lock-Volume $null; Pause-Return }
    'Q' { return }
    default { }
  }
}
