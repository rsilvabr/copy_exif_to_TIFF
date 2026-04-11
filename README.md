# copy_exif_to_TIFF

Copies EXIF metadata from JPEG to the corresponding TIFF. 
Optionally compresses the TIFF to ZIP/Deflate after copying.

Originally created for Fujifilm S5 Pro and S3 Pro users who export TIFFs via Hyper Utility — 
these TIFFs come without EXIF metadata. This script restores camera info, lens data, date/time, 
and GPS by copying EXIF from the corresponding JPEG files.

---

## Why this exists

The Fuji S5 Pro and S3 Pro record images in RAF (Fuji RAW) format. The original Fujifilm 
**Hyper Utility** software converts these to TIFF with excellent color rendering and the 
signature 12MP Super CCD interpolation — but the resulting TIFF **does not inherit EXIF** 
from the original RAF. Camera model, lens, date, time, and GPS are all blank.

This script solves that by copying EXIF from the JPEG to the TIFF.

### Two workflows supported:

**1. RAW + JPEG shooting (ideal)**
- Camera saves both RAF + JPEG
- JPEG has the EXIF metadata
- Export TIFF from Hyper Utility
- Run this script → TIFF now has EXIF from JPEG
- Result: Fuji colors + good 12MP interpolation + complete metadata

**2. RAW only shooting (also works)**
- You only have RAF files from the camera
- Export JPEG from any modern software (Capture One, Lightroom, Darktable, etc)
- The JPEG will have EXIF (date/time from the RAW)
- Export TIFF from Hyper Utility
- Run this script → EXIF copied from "modern JPEG" to "Hyper Utility TIFF"
- Result: Same benefits, even if you didn't shoot JPEG+RAW originally

### Supported cameras

- **Fuji S5 Pro** — Super CCD SR Pro, 12MP interpolated (2006)
- **Fuji S3 Pro** — Super CCD SR, 12MP interpolated (2004)
  - Note: S3 Pro can only shoot RAW **or** JPEG (not both simultaneously), 
    so workflow #2 (export JPEG from modern software) is the way to go

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
$Workers              = 8        # parallel threads (PS7 only)
$DryRun               = $false   # true = preview without modifying any files
$SkipIfTiffHasExif    = $true    # true = skip TIFFs that already have EXIF
$SkipLzwAsCompressed  = $false   # true = treat LZW as already compressed (skip ZIP re-compression)
$SafeMode             = $true    # true = skip multi-page TIFFs (scanner IR, Photoshop layers)
$IccPolicy            = "never"  # always | preserve_tiff | never (default: never — keep TIFF's ICC)
$CompressZip          = $false   # true = compress TIFF to ZIP after copying EXIF
$OutputDir            = ""       # "" = overwrite in place | "zip" = subfolder | "F:\ZIPs" = absolute
$StagingDir           = ""       # "" = disabled | "E:\staging" = write here, move after each group
$Overwrite            = $false    # true = overwrite existing output files
$AutoFind             = $false   # true = search subfolders for folders matching $FolderPattern
$FolderPattern        = "S5pro"  # folder name pattern for AutoFind mode
```

> **Why `$SkipLzwAsCompressed`?** LZW produces larger files on 16-bit TIFFs. Default (`$false`) converts LZW → ZIP. Set to `$true` if you want to keep LZW-compressed TIFFs as-is (treats them like ZIP/Deflate — skips re-compression).

> **Why `$SafeMode`?** Multi-page TIFFs (scanner IR files, Photoshop layers) store data in multiple IFDs with byte-offset pointers that break when external tools recompress the file. `$SafeMode = $true` (default) detects these before touching them and skips them entirely. Multi-page TIFFs are listed at the end of the log for manual review.

> **Why `$IccPolicy`?** When copying EXIF from JPEG to TIFF, the ICC profile can be copied too. Default (`"never"`) keeps the TIFF's original ICC — recommended when the TIFF is AdobeRGB and the JPEG is sRGB. `"always"` copies the JPEG's ICC regardless. `"preserve_tiff"` copies ICC from JPEG only if the TIFF has no ICC profile.

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

> `$SafeMode` adds another independent skip: if the TIFF has more than one IFD (multi-page), it is logged as `MULTI` and never touched, regardless of the flags above.

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
| `MULTI` | Multi-page TIFF skipped (SafeMode) |
| `ERROR` | Failure — file was not processed |
