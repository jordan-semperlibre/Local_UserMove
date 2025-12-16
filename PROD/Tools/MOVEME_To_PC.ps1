# Import MOVEME (From External drive to PC)
$ErrorActionPreference = 'SilentlyContinue'

function Wait-Enter {
    param([string]$Prompt = 'Press ENTER to continue...')
    [void](Read-Host -Prompt $Prompt)
}

function Get-VolumesFromDiskpart {
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
                Ltr    = if ($parts.Count -gt 1) { $parts[1].Trim() } else { "" }
                Label  = if ($parts.Count -gt 2) { $parts[2].Trim() } else { "" }
                Fs     = if ($parts.Count -gt 3) { $parts[3].Trim() } else { "" }
                Type   = if ($parts.Count -gt 4) { $parts[4].Trim() } else { "" }
                Size   = if ($parts.Count -gt 5) { $parts[5].Trim() } else { "" }
                Status = if ($parts.Count -gt 6) { $parts[6].Trim() } else { "" }
                Info   = if ($parts.Count -gt 7) { $parts[7].Trim() } else { "" }
            }
        }
    }
    return $rows
}

function Ensure-DriveLetter {
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

    $usedLetters = @(Get-PSDrive -PSProvider FileSystem | ForEach-Object { $_.Name.Trim().ToUpper() })
    $allCandidates = @()
    if ($PreferredLetters) { $allCandidates += $PreferredLetters }
    $allCandidates += @('D','E','F','G','H','I','J','K','L','M','N','O','P','Q','R','S','T','U','V','W','Y','Z')
    $candidates = $allCandidates | Select-Object -Unique

    foreach ($candidate in $candidates) {
        if ($usedLetters -contains $candidate) { continue }
        $tmp = [System.IO.Path]::GetTempFileName()
        $script = "select volume $number`nassign letter=$candidate"
        Set-Content -LiteralPath $tmp -Value $script -Encoding ASCII
        $null = cmd /c "diskpart /s `"$tmp`"" 2>$null
        Remove-Item -Force $tmp -ErrorAction SilentlyContinue
        Start-Sleep -Milliseconds 300
        $updated = Get-VolumesFromDiskpart | Where-Object { $_.Number -eq $number } | Select-Object -First 1
        $newLetter = if ($updated) { & $normalize $updated.Ltr } else { '' }
        if ($newLetter) { return ($newLetter + ':') }
    }

    return $null
}

function Pick-DriveLetter {
    param(
        [string]$PreferLabel='data',
        [string[]]$PreferredLetters = @('S','T','U','V','W','Y','Z','R','Q','P'),
        [string]$MenuTitle='Volumes',
        [string]$PromptLabel='',
        [string]$ContextMessage=''
    )

    $vols = Get-VolumesFromDiskpart | Where-Object { $_.Type -in 'Partition','Removable','CD-ROM' }
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
                if (Ensure-DriveLetter -Volume $vol -PreferredLetters $PreferredLetters) { $assigned = $true }
            }
        }
        if ($assigned) {
            $vols = Get-VolumesFromDiskpart | Where-Object { $_.Type -in 'Partition','Removable','CD-ROM' }
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($ContextMessage)) {
        Write-Host ""
        Write-Host $ContextMessage -ForegroundColor Yellow
    }

    $title = if ([string]::IsNullOrWhiteSpace($MenuTitle)) { 'Volumes' } else { $MenuTitle }
    Write-Host ("`n== {0} ==" -f $title) -ForegroundColor Cyan
    $index = 0
    foreach ($vol in $vols) {
        $index++
        $labelNorm = & $normalizeLabel $vol.Label
        $mark = ' '
        if ($target) {
            if ($labelNorm -eq $target) { $mark = '*' }
            elseif ($labelNorm -like "*$target*") { $mark = '~' }
        }
        $ltrDisplay = if ($vol.Ltr) { $vol.Ltr.Trim() } else { '--' }
        "{0,2}) {1}  Ltr={2,-2}  Label={3,-16}  Fs={4,-6}  Size={5}" -f $index,$mark,$ltrDisplay,$vol.Label,$vol.Fs,$vol.Size | Write-Host
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

    $defaultLetterDisplay = if ($defaultVolume -and $defaultVolume.Ltr) { $defaultVolume.Ltr.Trim().ToUpper() } else { '' }
    $prompt = "Select item # or drive letter"
    if (-not [string]::IsNullOrWhiteSpace($PromptLabel)) { $prompt += " for $PromptLabel" }
    if ($defaultLetterDisplay) { $prompt += " (default ${defaultLetterDisplay}:)" }
    $prompt += ':'

    $answer = Read-Host $prompt
    if ([string]::IsNullOrWhiteSpace($answer)) {
        if ($defaultVolume) {
            $letter = Ensure-DriveLetter -Volume $defaultVolume -PreferredLetters $PreferredLetters
            if ($letter) { return $letter }
        }
        return $null
    }

    if ($answer -match '^\d+$') {
        $idx = [int]$answer
        if ($idx -ge 1 -and $idx -le $vols.Count) {
            $selectedVolume = $vols[$idx-1]
            $letter = Ensure-DriveLetter -Volume $selectedVolume -PreferredLetters $PreferredLetters
            if ($letter) { return $letter }
        }
        return $null
    } else {
        $ltr = $answer.Trim().TrimEnd(':','\').ToUpper()
        if ($ltr.Length -eq 1) { return ($ltr + ':') }
        return $null
    }
}

Clear-Host
Write-Host "Import Data from External Drive to PC" -ForegroundColor Green

$data = Pick-DriveLetter -PreferLabel 'data' -MenuTitle 'Source Volumes' -PromptLabel 'the source drive' -ContextMessage 'Select the External drive that holds the MOVEME folder, It will be the volume labeled DATA.'
if (-not $data) { Write-Host "[ERROR] No source selected." -ForegroundColor Red; Wait-Enter; return }

$src  = Join-Path ($data + '\\') 'MOVEME'
if (-not (Test-Path $src)) { Write-Host "[ERROR] $src not found." -ForegroundColor Red; Wait-Enter; return }

$dest = 'C:\MOVEME'
New-Item -ItemType Directory -Force -Path $dest | Out-Null

try {
    $srcResolved = (Resolve-Path -LiteralPath $src).ProviderPath
} catch {
    Write-Host "[ERROR] Unable to resolve source path ${src}: $($_.Exception.Message)" -ForegroundColor Red
    Wait-Enter
    return
}

try {
    $destResolved = (Resolve-Path -LiteralPath $dest).ProviderPath
} catch {
    Write-Host "[ERROR] Unable to resolve destination path ${dest}: $($_.Exception.Message)" -ForegroundColor Red
    Wait-Enter
    return
}

$logDir = Join-Path ($data + '\\') 'Logs'
try {
    New-Item -ItemType Directory -Force -Path $logDir | Out-Null
} catch {
    $fallbackLogDir = Join-Path ([System.IO.Path]::GetTempPath()) 'MOVEME'
    Write-Host "[WARN] Unable to create log directory $logDir. Falling back to $fallbackLogDir. $($_.Exception.Message)" -ForegroundColor Yellow
    try {
        New-Item -ItemType Directory -Force -Path $fallbackLogDir | Out-Null
        $logDir = $fallbackLogDir
    } catch {
        Write-Host "[WARN] Failed to prepare fallback log directory $fallbackLogDir. Logs disabled. $($_.Exception.Message)" -ForegroundColor Yellow
        $logDir = $null
    }
}
$log = if ($logDir) { Join-Path $logDir ("Import_{0:yyyy-MM-dd_HH-mm-ss}.txt" -f (Get-Date)) } else { $null }

$copySucceeded = $false
if (Get-Command robocopy.exe -ErrorAction SilentlyContinue) {
    Write-Host "[INFO] Source: $srcResolved" -ForegroundColor DarkGray
    Write-Host "[INFO] Destination: $destResolved" -ForegroundColor DarkGray
    $robocopyArgs = @("$srcResolved", "$destResolved", '*.*', '/E', '/COPY:DAT', '/R:1', '/W:0', '/MT:32', '/Tee', '/V')
    if ($log) { $robocopyArgs += "/Log:$log" }
    Write-Host "[INFO] Running: robocopy $($robocopyArgs -join ' ')" -ForegroundColor DarkGray
    robocopy @robocopyArgs
    $rc = $LASTEXITCODE
    if ($rc -ge 8) { Write-Host "[ERROR] Robocopy failed ($rc)." -ForegroundColor Red; Wait-Enter; return }
    $copySucceeded = $true
} else {
    try {
        Copy-Item "$srcResolved\*" "$destResolved\" -Recurse -Force -ErrorAction Stop
        $copySucceeded = $true
    } catch {
        Write-Host "[ERROR] Copy-Item failed: $($_.Exception.Message)" -ForegroundColor Red
        Wait-Enter
        return
    }
}

$removed = $false
if ($copySucceeded) {
    try {
        Remove-Item -LiteralPath $src -Recurse -Force -ErrorAction Stop
        $removed = $true
    } catch {
        Write-Host "[WARN] Imported but failed to remove ${src}: $($_.Exception.Message)" -ForegroundColor Yellow
    }
}

if ($removed) {
    Write-Host "[DONE] Imported to $dest and removed $src" -ForegroundColor Cyan
} else {
    Write-Host "[DONE] Imported to $dest" -ForegroundColor Cyan
}
Wait-Enter
