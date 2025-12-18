# Export DATA (From PC - External Drive)
$ErrorActionPreference = 'Stop'

$script:log = $null

function Wait-Enter {
    param([string]$Prompt = 'Press ENTER to continue...')
    [void](Read-Host -Prompt $Prompt)
}

function Write-Log {
    param([string]$Message)
    if (-not $script:log) { return }
    try {
        Add-Content -LiteralPath $script:log -Value ("{0:yyyy-MM-dd HH:mm:ss} {1}" -f (Get-Date), $Message) -Encoding ASCII
    } catch {
        Write-Host "[WARN] Failed to write log entry: $($_.Exception.Message)" -ForegroundColor Yellow
    }
}

function Get-VolumesFromDiskpart {
    try {
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
    } catch {
        $msg = "Failed to query volumes: $($_.Exception.Message)"
        Write-Host "[ERROR] $msg" -ForegroundColor Red
        Write-Log "[ERROR] $msg"
        return @()
    }
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
        try {
            $tmp = [System.IO.Path]::GetTempFileName()
            $script = "select volume $number`nassign letter=$candidate"
            Set-Content -LiteralPath $tmp -Value $script -Encoding ASCII
            $null = cmd /c "diskpart /s `"$tmp`"" 2>$null
            Remove-Item -Force $tmp -ErrorAction SilentlyContinue
            Start-Sleep -Milliseconds 300
            $updated = Get-VolumesFromDiskpart | Where-Object { $_.Number -eq $number } | Select-Object -First 1
            $newLetter = if ($updated) { & $normalize $updated.Ltr } else { '' }
            if ($newLetter) { return ($newLetter + ':') }
        } catch {
            $msg = "Failed to assign drive letter for volume $number: $($_.Exception.Message)"
            Write-Host "[ERROR] $msg" -ForegroundColor Red
            Write-Log "[ERROR] $msg"
        }
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
Write-Host "Export Data from PC to External Drive" -ForegroundColor Green

$overallSucceeded = $true
$errorMessages = @()

$src = 'C:\MOVEME'
if (-not (Test-Path $src)) {
    $overallSucceeded = $false
    $msg = "$src not found."
    $errorMessages += $msg
    Write-Host "[ERROR] $msg" -ForegroundColor Red
    Write-Log "[ERROR] $msg"
}

$data = $null
if ($overallSucceeded) {
    $data = Pick-DriveLetter -PreferLabel 'data' -MenuTitle 'Destination Volumes' -PromptLabel 'the target location' -ContextMessage 'Select the EXTERNAL drive where MOVEME Data will be exported. Any existing MOVEME folder will be REMOVED.'
    if (-not $data) {
        $overallSucceeded = $false
        $msg = "No destination selected."
        $errorMessages += $msg
        Write-Host "[ERROR] $msg" -ForegroundColor Red
        Write-Log "[ERROR] $msg"
    } else {
        Write-Host "[OK] Using $data" -ForegroundColor Yellow
    }
}

$dest = $null
$logDir = $null
if ($overallSucceeded) {
    $dest = Join-Path ($data + '\\') 'MOVEME'
    $logDir = Join-Path ($data + '\\') 'Logs'
    try {
        New-Item -ItemType Directory -Force -Path $logDir | Out-Null
    } catch {
        $fallbackLogDir = Join-Path ([System.IO.Path]::GetTempPath()) 'MOVEME'
        $msg = "Unable to create log directory $logDir. Falling back to $fallbackLogDir. $($_.Exception.Message)"
        Write-Host "[WARN] $msg" -ForegroundColor Yellow
        Write-Log "[WARN] $msg"
        try {
            New-Item -ItemType Directory -Force -Path $fallbackLogDir | Out-Null
            $logDir = $fallbackLogDir
        } catch {
            $msg = "Failed to prepare fallback log directory $fallbackLogDir. Logs disabled. $($_.Exception.Message)"
            Write-Host "[WARN] $msg" -ForegroundColor Yellow
            Write-Log "[WARN] $msg"
            $logDir = $null
        }
    }
    if ($logDir) {
        $script:log = Join-Path $logDir ("Export_{0:yyyy-MM-dd_HH-mm-ss}.txt" -f (Get-Date))
    }
}

if (Test-Path -LiteralPath $dest) {
    $confirm = Read-Host "[WARN] ${dest} already exists on $data. Delete and recreate? (Y/N)"
    if ($confirm.Trim().ToUpper() -notin @('Y','YES')) {
        Write-Host "[ABORT] User declined to remove existing MOVEME folder." -ForegroundColor Yellow
        Wait-Enter
        return
    }

    Write-Host "[INFO] Removing existing MOVEME folder on $data" -ForegroundColor Yellow
    if ($log) { Add-Content -LiteralPath $log -Value ("[{0:yyyy-MM-dd HH:mm:ss}] Removing existing MOVEME at {1}" -f (Get-Date), $dest) }

    try {
        if (Get-Command robocopy.exe -ErrorAction SilentlyContinue) {
            $robocopyArgs = @("$src", "$dest", '*.*', '/E', '/COPY:DAT', '/R:1', '/W:0', '/MT:32', '/Tee', '/XF', 'desktop.ini', '/XD','System Volume Information', '$RECYCLE.BIN')
            if ($script:log) { $robocopyArgs += "/Log:$script:log" }
            robocopy @robocopyArgs
            $rc = $LASTEXITCODE
            if ($rc -ge 8) { throw "Robocopy failed ($rc)." }
        } else {
            Copy-Item "$src\\*" "$dest\\" -Recurse -Force -ErrorAction Stop
        }
    } catch {
        $overallSucceeded = $false
        $msg = "Data transfer failed: $($_.Exception.Message)"
        $errorMessages += $msg
        Write-Host "[ERROR] $msg" -ForegroundColor Red
        Write-Log "[ERROR] $msg"
    }
}

if ($overallSucceeded) {
    Write-Host "[DONE] Exported to $dest" -ForegroundColor Cyan
} else {
    Write-Host "[WARN] Export incomplete." -ForegroundColor Yellow
}

if ($errorMessages.Count -gt 0) {
    Write-Host "[SUMMARY] Transfer completed with errors:" -ForegroundColor Yellow
    foreach ($err in $errorMessages) { Write-Host " - $err" -ForegroundColor Yellow }
} else {
    Write-Host "[SUMMARY] Transfer completed successfully." -ForegroundColor Green
}

Wait-Enter
