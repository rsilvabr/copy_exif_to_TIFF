# copy_exif_to_TIFF

Copies EXIF metadata from JPEG to the corresponding TIFF. 
Optionally compresses the TIFF to ZIP/Deflate after copying.
Useful to TIFFs exported by Fujifilm Hyper Utility (Fuji S5 Pro), since they usually have no metadata - the script can copy EXIF from the corresponding JPEGs in the same folder or in nearby folders following a pattern. 

---

## Why this exists

The Fuji S5 Pro records images in RAF (Fuji RAW) format. Hyper Utility converts these to TIFF,
but the resulting TIFF **does not inherit EXIF from the original** — camera model, lens, date,
time, and GPS are all blank. The date on the TIFF is the export time, not the capture time.

The JPEG exported by the camera with the RAW file (for RAW + JPEG shooting) has the EXIF metadata.
This script uses the JPEG as the source and copies its EXIF to the corresponding TIFF.

For the case of no JPEG available (only RAW shooting), exporting JPEGs from the RAW files 
using a modern software (CaptureOne, Lightroom, Darktable, etc) may work. Not tested.

---

## Requirements

**PowerShell 7** — Windows ships with PowerShell 5.1, which does not support `ForEach-Object -Parallel`.
Use the PS7 version for parallel processing.

```powershell
winget install --id Microsoft.PowerShell --source winget
```

After installing, use **PowerShell 7** (black icon in Start menu, executable `pwsh.exe`).
PS5.1 remains installed alongside it — the two coexist.

A **PowerShell 5.1 compatible version** is also included (`copy_exif_to_TIFF_ps5.ps1`).
It runs sequentially but works on any Windows system without installing PS7.

**ExifTool** — https://exiftool.org → rename the executable to `exiftool.exe` and add to PATH.

**ImageMagick** (only if `$CompressZip = $true`) — https://imagemagick.org

---

## Disclaimer

These tools were made for my personal workflow (with the help of Claude). Use at your own risk — I am not responsible for any issues you may encounter.
If you choose to use it and find any errors/bugs, please let me know.

---
## Files

| File | Description |
|------|-------------|
| `copy_exif_to_TIFF_ps7.ps1` | PowerShell 7 — parallel processing |
| `copy_exif_to_TIFF_ps5.ps1` | PowerShell 5.1 compatible — sequential |

Both versions can be run as a `.ps1` file or pasted directly into a terminal opened
in the folder containing your TIFFs.

---

## Quick start

```powershell
# Navigate to the folder with your TIFFs, then run:
.\copy_exif_to_TIFF_ps7.ps1
```

Or paste the entire script into a PowerShell 7 terminal opened in that folder.

---

## Supported folder structures

The script automatically detects which of these structures is in use:

```
1. JPEG and TIFF in the same folder:
   folder/photo.jpg
   folder/photo.tif

2. TIFF/ subfolder next to JPEGs:
   folder/photo.jpg
   folder/TIFF/photo.tif

3. Separate JPEG/ and TIFF/ subfolders:
   folder/JPEG/photo.jpg
   folder/TIFF/photo.tif

4. TIFFs in root, JPEGs in JPEG/ subfolder:
   folder/photo.tif
   folder/JPEG/photo.jpg
```

**Numeric suffix handling:** Hyper Utility may export multiple versions with a numeric suffix.
The script strips `_N` automatically when searching for the matching JPEG:
```
_DSF0007_1.tif  →  looks for  _DSF0007.jpg
_DSF0007_2.tif  →  looks for  _DSF0007.jpg
```

---

## Settings

```powershell
$Workers           = 8        # parallel threads (PS7 only)
$DryRun            = $false   # true = preview without modifying any files
$SkipIfTiffHasExif = $true    # true = skip TIFFs that already have EXIF
$CompressZip       = $false   # true = compress TIFF to ZIP after copying EXIF
$OutputDir         = ""       # "" = overwrite in place | "zip" = subfolder | "F:\ZIPs" = absolute
$StagingDir        = ""       # "" = disabled | "E:\staging" = write here, move after each group
$Overwrite         = $false   # true = overwrite existing output files
$AutoFind          = $false   # true = search subfolders for folders matching $FolderPattern
$FolderPattern     = "S5pro"  # folder name pattern for AutoFind mode
```

---

## AutoFind mode

When `$AutoFind = $true`, the script recursively searches from the current folder
for folders whose name contains `$FolderPattern`, and processes each one.

```
F:\2024\240115_Tokyo_S5pro\  ← found and processed
F:\2024\240820_Nikko_S5pro\  ← found and processed
F:\2024\240901_Kyoto_D810\   ← ignored (no "S5pro" in name)
```

AutoFind never enters `Logs\` folders to avoid processing the script's own log files.

---

## SkipIfTiffHasExif + CompressZip behavior

The two flags are independent — `$SkipIfTiffHasExif` only controls EXIF copying, not compression.

| TIFF has EXIF? | TIFF compressed? | Result |
|----------------|-----------------|--------|
| No | No | Copy EXIF → compress ZIP |
| **Yes** | **No** | **Skip EXIF → compress ZIP anyway** |
| No | Yes | Copy EXIF → skip ZIP |
| Yes | Yes | Skip everything |

---

## Log

```
<current_folder>\Logs\copy_exif_to_TIFF\YYYYMMDD_HHMMSS.log
```

| Status | Meaning |
|--------|---------|
| `OK` | EXIF copied successfully |
| `OK+ZIP` | EXIF copied and TIFF compressed |
| `OK+SKIP-ZIP` | EXIF copied, ZIP skipped (already compressed) |
| `SKIP` | Skipped (already has EXIF, or output exists) |
| `MISS` | No matching JPEG found |
| `ERROR` | Failure — file was not processed |
