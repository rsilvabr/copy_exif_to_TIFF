# ── SETTINGS ──────────────────────────────────────────────────────
$Workers           = 16
$DryRun            = $false
$SkipIfTiffHasExif = $true
$SkipLzwAsCompressed = $false  # true = treat LZW as already compressed (skip ZIP re-compression)
$SafeMode          = $true      # true = skip multi-page TIFFs (scanner IR, Photoshop layers)
                                # false = compress all TIFFs including multi-page ones
$IccPolicy         = "never"   # always | preserve_tiff | never (default: never — keep TIFF's original ICC)
$CompressZip       = $true
$OutputDir         = ""
$StagingDir        = ""
$Overwrite         = $true
$AutoFind          = $true
$FolderPattern     = "S5pro"
$MagickTimeout     = 30        # seconds timeout for magick identify (prevents hang on corrupted files)
# ──────────────────────────────────────────────────────────────────

# ── Cleanup on interrupt ─────────────────────────────────────────
$script:cleanupDirs = @()
if ($StagingDir) { $script:cleanupDirs += $StagingDir }

trap {
    Write-Log "Interrupted! Cleaning up staging files..." "WARN"
    foreach ($dir in $script:cleanupDirs) {
        if (Test-Path -LiteralPath $dir) {
            Remove-Item -Path "$dir\*" -Force -ErrorAction SilentlyContinue
        }
    }
    break
}

# ── Logging ───────────────────────────────────────────────────────
$scriptName = "Copy-S5Pro-Exif"
$logDir     = Join-Path $PWD.Path "Logs\$scriptName"
[System.IO.Directory]::CreateDirectory($logDir) | Out-Null
$logFile    = Join-Path $logDir "$(Get-Date -Format 'yyyyMMdd_HHmmss').log"

function Write-Log {
    param([string]$msg, [string]$level = "INFO")
    $line = "$(Get-Date -Format 'HH:mm:ss') | $level | $msg"
    Write-Host $line
    [System.IO.File]::AppendAllText($logFile, $line + [System.Environment]::NewLine)
}

$script:counterTotal = 0
$script:total        = 0
$script:okTotal      = 0
$script:skipTotal    = 0
$script:missTotal    = 0
$script:errTotal     = 0
$script:multiTotal    = 0
$script:multiPagePaths = [System.Collections.Concurrent.ConcurrentBag[string]]::new()

function Process-Line {
    param([string]$line)
    $script:counterTotal++
    $lvl = "INFO"
    if     ($line -match '^OK')    { $script:okTotal++ }
    elseif ($line -match '^SKIP')  { $script:skipTotal++ }
    elseif ($line -match '^MISS')  { $script:missTotal++; $lvl = "WARN" }
    elseif ($line -match '^ERROR')  { $script:errTotal++;  $lvl = "ERROR" }
    elseif ($line -match '^MULTI')  { $script:multiTotal++; $lvl = "WARN" }
    Write-Log "[$($script:counterTotal)/$($script:total)] $line" $lvl
}

function Invoke-S5ProFolder {
    param([string]$RootPath, [bool]$IsRecurse)

    $allFiles  = Get-ChildItem -LiteralPath $RootPath -File -Recurse:$IsRecurse
    $jpgFiles  = $allFiles | Where-Object { $_.Extension -match '^\.(jpg|jpeg)$' }
    $tiffFiles = $allFiles | Where-Object { $_.Extension -match '^\.(tif|tiff)$' }

    if ($tiffFiles.Count -eq 0) { Write-Log "No TIFFs found in: $RootPath" "WARN"; return }

    $script:total += $tiffFiles.Count
    Write-Log "TIFFs: $($tiffFiles.Count) | JPEGs: $($jpgFiles.Count)"

    # Build JPEG index
    $jpgIndex = @{}
    foreach ($j in $jpgFiles) {
        $key = ($j.DirectoryName.ToLowerInvariant() + "|" + $j.BaseName.ToLowerInvariant())
        if (-not $jpgIndex.ContainsKey($key)) { $jpgIndex[$key] = $j.FullName }
        elseif ($j.Extension.ToLowerInvariant() -eq ".jpg") { $jpgIndex[$key] = $j.FullName }
    }

    function Find-JpegPair {
        param([System.IO.FileInfo]$tif)
        $dir    = $tif.DirectoryName
        $base   = $tif.BaseName
        $parent = Split-Path $dir -Parent
        $candidates = @($base)
        $stripped = ($base -replace '(_\d+)$', '')
        if ($stripped -ne $base -and $stripped.Length -gt 0) { $candidates += $stripped }
        $searchDirs = @($dir, (Join-Path $dir "JPEG"), (Join-Path $dir "JPG"),
                        $parent, (Join-Path $parent "JPEG"), (Join-Path $parent "JPG")) |
                      Where-Object { $_ -and (Test-Path -LiteralPath $_) }
        foreach ($b in $candidates) {
            foreach ($d in $searchDirs) {
                $key = ($d.ToLowerInvariant() + "|" + $b.ToLowerInvariant())
                if ($jpgIndex.ContainsKey($key)) { return @{ Path = $jpgIndex[$key]; UsedBase = $b } }
            }
        }
        return $null
    }

    $groups = $tiffFiles | Group-Object { $_.DirectoryName }

    foreach ($group in $groups) {
        $groupDir   = $group.Name
        $groupFiles = $group.Group

        if ($groups.Count -gt 1 -or $AutoFind) {
            Write-Log ""; Write-Log "── Group: $groupDir ($($groupFiles.Count) file(s))"
        }

        $finalDir = if ($OutputDir) { $OutputDir } else { $groupDir }
        $writeDir = if ($StagingDir -and -not $DryRun) { $StagingDir } else { $finalDir }

        if ($CompressZip -and $StagingDir -and -not $DryRun) { [System.IO.Directory]::CreateDirectory($StagingDir) | Out-Null }
        if ($CompressZip -and $OutputDir)                    { [System.IO.Directory]::CreateDirectory($OutputDir)  | Out-Null }

        # Resolve TIFF→JPEG pairs
        $pairs = @(foreach ($tif in $groupFiles) {
            $pair = Find-JpegPair $tif
            [PSCustomObject]@{
                Tiff     = $tif.FullName
                TifName  = $tif.Name
                TifBase  = $tif.BaseName
                Jpeg     = if ($pair) { $pair.Path }    else { $null }
                UsedBase = if ($pair) { $pair.UsedBase } else { $null }
            }
        })

        if ($pairs.Count -eq 0) { continue }

        # Synchronous parallel — more reliable than -AsJob when run from terminal
        $writeDirCapture  = $writeDir
        $finalDirCapture  = $finalDir
        $skipExifCapture  = $SkipIfTiffHasExif
        $dryCapture       = $DryRun
        $compressCapture  = $CompressZip
        $overCapture      = $Overwrite
        $skipLzwCapture   = $SkipLzwAsCompressed
        $safeModeCapture  = $SafeMode
        $multiPageBagCapture = $script:multiPagePaths
        $iccPolicyCapture = $IccPolicy

        $results = $pairs | ForEach-Object -ThrottleLimit $Workers -Parallel {
            $p         = $_
            $skipExifL = $using:skipExifCapture
            $dryL      = $using:dryCapture
            $compressL = $using:compressCapture
            $writeDirL = $using:writeDirCapture
            $finalDirL = $using:finalDirCapture
            $overL     = $using:overCapture
            $skipLzwL  = $using:skipLzwCapture
            $safeModeL = $using:safeModeCapture
            $bagL      = $using:multiPageBagCapture
            $iccPolicyL = $using:iccPolicyCapture

            if (-not $p.Jpeg) {
                return @{ Result = "MISS | $($p.TifName) | no matching JPEG (base: $($p.TifBase))"; StagingName = $null; OriginalName = $p.TifName }
            }

            if ($skipExifL) {
                $firstExif = exiftool -q -q -G1 -s -EXIF:all $p.Tiff 2>$null | Select-Object -First 1
                if ($firstExif) { return @{ Result = "SKIP (already has EXIF) | $($p.TifName)"; StagingName = $null; OriginalName = $p.TifName } }
            }

            if ($dryL) {
                $zipInfo = if ($compressL) { " + ZIP" } else { "" }
                return @{ Result = "DRY (EXIF$zipInfo) | $($p.TifName) <= $([IO.Path]::GetFileName($p.Jpeg))"; StagingName = $null; OriginalName = $p.TifName }
            }

            if ($safeModeL) {
                $magickTimeoutSec = 30  # Fixed timeout value - don't use $using inside Start-Job
                $pageCountJob = Start-Job { magick identify $using:p.Tiff 2>$null }
                $pageCountJob | Wait-Job -Timeout $magickTimeoutSec | Out-Null
                if ($pageCountJob.State -eq 'Running') {
                    Stop-Job $pageCountJob
                    Remove-Job $pageCountJob
                    return @{ Result = "ERROR (magick timeout) | $($p.TifName) | possibly corrupted"; StagingName = $null; OriginalName = $p.TifName }
                }
                $pageCount = ($pageCountJob | Receive-Job | Measure-Object -Line).Lines
                Remove-Job $pageCountJob
                if ($pageCount -gt 1) {
                    $bagL.Add($p.Tiff) | Out-Null
                    return @{ Result = "MULTI ($pageCount IFDs — skipped) | $($p.TifName)"; StagingName = $null; OriginalName = $p.TifName }
                }
            }

            # Check if TIFF already has ICC (fixed logic - don't reset $LASTEXITCODE)
            $tiffHasIcc = $false
            if ($iccPolicyL -eq "preserve_tiff" -or $iccPolicyL -eq "always") {
                $iccCheck = exiftool -s -s -s -ICC_Profile:all $p.Tiff 2>$null
                # Don't check $LASTEXITCODE here - just check if output exists
                if ($iccCheck -and $iccCheck.Length -gt 0) { $tiffHasIcc = $true }
            }
            $copyIcc = ($iccPolicyL -eq "always") -or ($iccPolicyL -eq "preserve_tiff" -and -not $tiffHasIcc)
            $iccTag = if ($copyIcc) { "-ICC_Profile" } else { "" }

            $tagsArgs = @("-tagsfromfile", $p.Jpeg, "-EXIF:All", "-XMP:All", "-IPTC:All")
            if ($iccTag) { $tagsArgs += $iccTag }
            $tagsArgs += "-unsafe", $p.Tiff

            exiftool -q -q -overwrite_original -P @tagsArgs | Out-Null
            if ($LASTEXITCODE -ne 0) { return @{ Result = "ERROR (exiftool EXIF) | $($p.TifName)"; StagingName = $null; OriginalName = $p.TifName } }

            if (-not $compressL) {
                return @{ Result = "OK | $($p.TifName) <= $([IO.Path]::GetFileName($p.Jpeg))"; StagingName = $null; OriginalName = $p.TifName }
            }

            $comp = exiftool -s -s -s -Compression $p.Tiff 2>$null
            if ($LASTEXITCODE -ne 0 -or -not $comp) {
                return @{ Result = "ERROR (exiftool check) | $($p.TifName) | cannot detect compression"; StagingName = $null; OriginalName = $p.TifName }
            }
            if ($comp -match $(if ($skipLzwL) { 'Deflate|ZIP|LZW' } else { 'Deflate|ZIP' })) {
                return @{ Result = "OK+SKIP-ZIP ($comp) | $($p.TifName)"; StagingName = $null; OriginalName = $p.TifName }
            }

            $stagingName = "$([guid]::NewGuid().ToString('N'))_$($p.TifName)"
            $writeDst = Join-Path $writeDirL $stagingName
            $finalDst = Join-Path $finalDirL $p.TifName

            if ((Test-Path -LiteralPath $finalDst) -and -not $overL -and ($finalDst -ne $p.Tiff)) {
                return @{ Result = "OK+SKIP-ZIP (exists) | $($p.TifName)"; StagingName = $null; OriginalName = $p.TifName }
            }

            magick -quiet $p.Tiff -compress zip $writeDst 2>$null
            if ($LASTEXITCODE -ne 0) { return @{ Result = "ERROR (magick ZIP) | $($p.TifName)"; StagingName = $null; OriginalName = $p.TifName } }

            exiftool -q -q -overwrite_original -tagsfromfile $p.Tiff -all:all -unsafe $writeDst | Out-Null
            return @{ Result = "OK+ZIP | $($p.TifName) <= $([IO.Path]::GetFileName($p.Jpeg))"; StagingName = $stagingName; OriginalName = $p.TifName }
        }

        # Process results and build staging map
        $script:groupStagingMap = @{}
        foreach ($r in $results) {
            if ($r.StagingName) { $script:groupStagingMap[$r.OriginalName] = $r.StagingName }
            Process-Line $r.Result
        }

        # Move from staging to final destination (with integrity check and UUID mapping)
        if ($CompressZip -and $StagingDir -and -not $DryRun) {
            $moved = 0
            foreach ($tif in $groupFiles) {
                # Use UUID-mapped staging name if available
                $originalName = $tif.Name
                if ($script:groupStagingMap.ContainsKey($originalName)) {
                    $stagingName = $script:groupStagingMap[$originalName]
                    $stagePath = Join-Path $StagingDir $stagingName
                } else {
                    $stagePath = Join-Path $StagingDir $originalName
                }
                $destPath  = Join-Path $finalDir   $originalName
                if ((Test-Path -LiteralPath $stagePath) -and $stagePath -ne $destPath) {
                    $stageSize = (Get-Item -LiteralPath $stagePath).Length
                    Move-Item -Force -LiteralPath $stagePath -Destination $destPath
                    # Verify move succeeded
                    if ((Test-Path -LiteralPath $destPath) -and ((Get-Item -LiteralPath $destPath).Length -eq $stageSize)) {
                        $moved++
                    } else {
                        Write-Log "ERROR (move failed) | $originalName" "ERROR"
                    }
                }
            }
            if ($moved -gt 0) { Write-Log "  → Moved $moved file(s) → $finalDir" }
        }
    }
}

# ── Entry point ─────────────────────────────────────────────────────
$root = $PWD.Path
Write-Log "Log: $logFile"
Write-Log "Workers: $Workers | CompressZip: $CompressZip | SkipIfTiffHasExif: $SkipIfTiffHasExif | OutputDir: $(if ($OutputDir) { $OutputDir } else { '(overwrite in place)' }) | Staging: $(if ($StagingDir) { $StagingDir } else { 'disabled' }) | DryRun: $DryRun"

if ($AutoFind) {
    Write-Log "AutoFind mode | Pattern: '$FolderPattern' | Root: $root"
    $matchingFolders = Get-ChildItem -LiteralPath $root -Directory -Recurse |
                       Where-Object { $_.Name -like "*$FolderPattern*" -and $_.FullName -notlike "*\Logs\*" }

    if ($matchingFolders.Count -eq 0) {
        Write-Log "No folders matching '$FolderPattern' found in: $root" "WARN"
    } else {
        Write-Log "Folders found: $($matchingFolders.Count)"
        foreach ($f in $matchingFolders) { Write-Log "  $($f.FullName)" }
        Write-Log ""
        foreach ($folder in $matchingFolders) {
            Write-Log "════ Processing: $($folder.FullName)"
            Invoke-S5ProFolder -RootPath $folder.FullName -IsRecurse $false
            Write-Log ""
        }
    }
} else {
    Write-Log "Root: $root"
    Invoke-S5ProFolder -RootPath $root -IsRecurse $false
}

Write-Log ""
Write-Log ("─" * 50)
Write-Log "Done: $($script:okTotal) OK | $($script:skipTotal) skipped | $($script:missTotal) no JPEG pair | $($script:multiTotal) multi-page | $($script:errTotal) errors | $($script:counterTotal)/$($script:total) processed"

if ($script:multiTotal -gt 0) {
    Write-Log ""
    Write-Log "── Multi-page TIFFs found (not touched):"
    foreach ($p in ($script:multiPagePaths | Sort-Object)) {
        Write-Log "   $p" "WARN"
    }
}
Write-Log "Log: $logFile"