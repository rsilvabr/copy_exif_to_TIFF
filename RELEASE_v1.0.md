# copy_exif_to_TIFF v1.0 — Stable Release

## What This Tool Does

**Copy EXIF/XMP/IPTC metadata from JPEG to TIFF** — restores metadata to TIFF files that lost it during conversion (common with Fuji S5 Pro and similar workflows).

## Key Features

| Feature | Benefit |
|---------|---------|
| **Auto-Find Pairs** | Automatically matches TIFF files with their corresponding JPEGs by filename |
| **Flexible Search** | Looks for JPEGs in same folder, "JPEG/JPG" subfolders, and parent directories |
| **Optional ZIP Compression** | Compress TIFF to ZIP/Deflate after copying metadata (optional) |
| **Safe Mode** | Skips multi-page TIFFs (scanners, Photoshop layers) to prevent corruption |
| **ICC Policy Control** | Choose whether to copy ICC profile from JPEG or preserve TIFF's original |
| **Smart Skip** | Option to skip TIFFs that already have EXIF metadata |
| **Staging Support** | Write to SSD staging first, then move to final destination |
| **Detailed Logging** | Per-session logs with timestamps for audit trail |

## Use Case Example

**Fuji S5 Pro Workflow:**
- Camera saves: RAF → JPEG (with EXIF) + TIFF (no EXIF)
- After editing: TIFF has image data but no metadata
- This tool: Copies EXIF from JPEG to TIFF automatically

## Requirements

- Windows PowerShell 5.1 or PowerShell 7+
- ImageMagick (`magick` command) — for ZIP compression and multi-page detection
- ExifTool (`exiftool` command) — for metadata operations

## Quick Start

1. Place script in parent folder containing your TIFFs and JPEGs
2. Edit settings at the top (especially `$FolderPattern` for auto-find)
3. Run: `.\copy_exif_to_TIFF_ps7.ps1` (or `_ps5` for PowerShell 5.1)

## Settings Highlights

```powershell
$FolderPattern     = "S5pro"    # Auto-find folders containing this pattern
$SkipIfTiffHasExif = $true      # Skip TIFFs that already have metadata
$CompressZip       = $true      # Also compress TIFF to ZIP/Deflate
$SafeMode          = $true      # Skip multi-page TIFFs (recommended)
$IccPolicy         = "never"    # "never" = keep TIFF's ICC, "always" = copy JPEG's ICC
$StagingDir        = ""         # SSD staging path (optional)
```

## How It Works

1. **Scans** for TIFF files in the folder structure
2. **Finds** matching JPEG files (same base name, flexible location)
3. **Copies** EXIF, XMP, and IPTC metadata from JPEG to TIFF
4. **Optionally** compresses TIFF to ZIP/Deflate format
5. **Logs** all operations for review

---

**Perfect companion to** [jxl-photo](https://github.com/rsilvabr/jxl-photo) — restore your metadata first, then convert to JPEG XL for archival.
