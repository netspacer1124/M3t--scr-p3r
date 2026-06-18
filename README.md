# M3t--scr-p3r
a metadata scraper for all types of files and URLs
# m3eta-scr@p3r

A Debian/Linux metadata collection utility written as a single Bash script.

## Features

- Extract metadata from:
  - Images
  - PDFs
  - Audio files
  - Video files
  - Arbitrary binary files
  - URLs

- Collects:
  - File hashes (SHA-256)
  - File size
  - MIME type
  - File type
  - Ownership and permissions
  - Timestamps
  - EXIF metadata
  - PDF metadata
  - Media metadata
  - HTTP headers
  - Basic content fingerprints

- Output formats:
  - Human-readable text reports
  - JSON reports

## Requirements

Recommended:

```bash
sudo apt update
sudo apt install \
    exiftool \
    file \
    curl \
    poppler-utils \
    imagemagick \
    mediainfo \
    jq
```

## Installation

```bash
git clone https://github.com/YOUR_USERNAME/m3eta-scr-p3r.git
cd m3eta-scr-p3r
chmod +x meta_scraper_cli.sh
```

## Usage

### Local File

```bash
./meta_scraper_cli.sh -f document.pdf
```

### Image

```bash
./meta_scraper_cli.sh -f image.jpg
```

### URL

```bash
./meta_scraper_cli.sh -u https://example.com/file.pdf
```

### JSON Output

```bash
./meta_scraper_cli.sh -u https://example.com/file.pdf -j
```

### Custom Output Directory

```bash
./meta_scraper_cli.sh -i sample.pdf -o reports
```

## Example Report Contents

- SHA256 Hash
- MIME Type
- EXIF Tags
- PDF Properties
- Media Information
- HTTP Headers
- Ownership Information
- Timestamps

## Output

Reports are written to:

```text
meta_out_YYYYMMDD_HHMMSS/
```

Example:

```text
sample.pdf.report.txt
sample.pdf.report.json
```

## Disclaimer

This tool is intended for digital forensics, metadata analysis, OSINT, incident response, and file inspection on systems you are authorized to analyze.
