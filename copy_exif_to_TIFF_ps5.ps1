# ── SETTINGS ─────────────────────────────────────────────────
$Workers           = 16
$DryRun            = $false
$SkipIfTiffHasExif = $true
$CompressZip       = $true
$OutputDir         = ""
$StagingDir        = ""
$Overwrite         = $true
$AutoFind          = $true
$FolderPattern     = "S5pro"
# ──────────────────────────────────────────────────────────────────

# ── Logging ───────────────────────────────────────────────────────────
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

function Process-Results {
    param($lines)
    foreach ($line in $lines) {
        $script:counterTotal++
        $lvl = "INFO"
        if     ($line -match '^OK')   { $script:okTotal++ }
        elseif ($line -match '^SKIP') { $script:skipTotal++ }
        elseif ($line -match '^MISS') { $script:missTotal++; $lvl = "WARN" }
        elseif ($line -match '^ERROR') { $script:errTotal++;  $lvl = "ERROR" }
        Write-Log "[$($script:counterTotal)/$($script:total)] $line" $lvl
    }
}

function Invoke-S5ProFolder {
    param([string]$RootPath, [bool]$IsRecurse)

    $allFiles  = Get-ChildItem -LiteralPath $RootPath -File -Recurse:$IsRecurse
    $jpgFiles  = $allFiles | Where-Object { $_.Extension -match '^\.(jpg|jpeg)$' }
    $tiffFiles = $allFiles | Where-Object { $_.Extension -match '^\.(tif|tiff)$' }

    if ($tiffFiles.Count -eq 0) {
        Write-Log "No TIFFs found in: $RootPath" "WARN"
        return
    }

    $script:total += $tiffFiles.Count
    Write-Log "TIFFs: $($tiffFiles.Count) | JPEGs: $($jpgFiles.Count)"

    $jpgIndex = @{}
    foreach ($j in $jpgFiles) {
        $key = ($j.DirectoryName.ToLowerInvariant() + "|" + $j.BaseName.ToLowerInvariant())
        if (-not $jpgIndex.ContainsKey($key)) {
            $jpgIndex[$key] = $j.FullName
        } elseif ($j.Extension.ToLowerInvariant() -eq ".jpg") {
            $jpgIndex[$key] = $j.FullName
        }
    }

    function Find-JpegPair {
        param([System.IO.FileInfo]$tif)
        $dir    = $tif.DirectoryName
        $base   = $tif.BaseName
        $parent = Split-Path $dir -Parent

        $candidates = @($base)
        $stripped = ($base -replace '(_\d+)$', '')
        if ($stripped -ne $base -and $stripped.Length -gt 0) { $candidates += $stripped }

        $searchDirs = @(
            $dir,
            (Join-Path $dir    "JPEG"),
            (Join-Path $dir    "JPG"),
            $parent,
            (Join-Path $parent "JPEG"),
            (Join-Path $parent "JPG")
        ) | Where-Object { $_ -and (Test-Path -LiteralPath $_) }

        foreach ($b in $candidates) {
            foreach ($d in $searchDirs) {
                $key = ($d.ToLowerInvariant() + "|" + $b.ToLowerInvariant())
                if ($jpgIndex.ContainsKey($key)) {
                    return @{ Path = $jpgIndex[$key]; UsedBase = $b }
                }
            }
        }
        return $null
    }

    $groups = $tiffFiles | Group-Object { $_.DirectoryName }

    foreach ($group in $groups) {
        $groupDir   = $group.Name
        $groupFiles = $group.Group

        if ($groups.Count -gt 1 -or $AutoFind) {
            Write-Log ""
            Write-Log "── Group: $groupDir ($($groupFiles.Count) file(s))"
        }

        $finalDir = if ($OutputDir)                            { $OutputDir }  else { $groupDir }
        $writeDir = if ($StagingDir -and -not $DryRun)         { $StagingDir } else { $finalDir }

        if ($CompressZip -and $StagingDir -and -not $DryRun) { [System.IO.Directory]::CreateDirectory($StagingDir) | Out-Null }
        if ($CompressZip -and $OutputDir)                    { [System.IO.Directory]::CreateDirectory($OutputDir)  | Out-Null }

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

            # Sequential — compatible with PowerShell 5.1
        $results = foreach ($p in $pairs) {
            $skipExifL = $SkipIfTiffHasExif
            $dryL      = $DryRun
            $compressL = $CompressZip
            $writeDirL = $writeDir
            $finalDirL = $finalDir
            $overL     = $Overwrite

            if (-not $p.Jpeg) {
                "MISS | $($p.TifName) | no matching JPEG (base: $($p.TifBase))"
                continue
            }

            if ($skipExifL) {
                $firstExif = exiftool -q -q -G1 -s -EXIF:all $p.Tiff 2>$null | Select-Object -First 1
                if ($firstExif) { "SKIP (already has EXIF) | $($p.TifName)"; continue }
            }

            if ($dryL) {
                $zipInfo = if ($compressL) { " + ZIP" } else { "" }
                "DRY (EXIF$zipInfo) | $($p.TifName) <= $([IO.Path]::GetFileName($p.Jpeg))"
                continue
            }

            exiftool -q -q -overwrite_original -P `
                -tagsfromfile $p.Jpeg `
                -EXIF:All -XMP:All -IPTC:All -ICC_Profile -unsafe `
                $p.Tiff | Out-Null
            if ($LASTEXITCODE -ne 0) { "ERROR (exiftool EXIF) | $($p.TifName)"; continue }

            if (-not $compressL) { "OK | $($p.TifName) <= $([IO.Path]::GetFileName($p.Jpeg))"; continue }

            $comp = exiftool -s -s -s -Compression $p.Tiff 2>$null
            if ($comp -match 'Deflate|ZIP|LZW') { "OK+SKIP-ZIP ($comp) | $($p.TifName)"; continue }

            $writeDst = Join-Path $writeDirL $p.TifName
            $finalDst = Join-Path $finalDirL $p.TifName

            if ((Test-Path -LiteralPath $finalDst) -and -not $overL -and ($finalDst -ne $p.Tiff)) {
                "OK+SKIP-ZIP (existe) | $($p.TifName)"; continue
            }

            magick -quiet $p.Tiff -compress zip $writeDst 2>$null
            if ($LASTEXITCODE -ne 0) { "ERROR (magick ZIP) | $($p.TifName)"; continue }

            exiftool -q -q -overwrite_original -tagsfromfile $p.Tiff -all:all -unsafe $writeDst | Out-Null
            "OK+ZIP | $($p.TifName) <= $([IO.Path]::GetFileName($p.Jpeg))"
        }

        foreach ($line in $results) { Process-Results @($line) }

        if ($CompressZip -and $StagingDir -and -not $DryRun) {
            $moved = 0
            foreach ($tif in $groupFiles) {
                $stagePath = Join-Path $StagingDir $tif.Name
                $destPath  = Join-Path $finalDir   $tif.Name
                if ((Test-Path -LiteralPath $stagePath) -and $stagePath -ne $destPath) {
                    Move-Item -Force -LiteralPath $stagePath -Destination $destPath
                    $moved++
                }
            }
            if ($moved -gt 0) { Write-Log "  → Moved $moved file(s) → $finalDir" }
        }
    }
}

# ── Entry point ────────────────────────────────────────────────────
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
Write-Log "Done: $($script:okTotal) OK | $($script:skipTotal) skipped | $($script:missTotal) no JPEG pair | $($script:errTotal) errors | $($script:counterTotal)/$($script:total) processed"
Write-Log "Log: $logFile"