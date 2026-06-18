#!/usr/bin/env bash
set -euo pipefail

# meta_scraper_cli.sh
# Generic metadata collector for URLs and local files.
# Debian-friendly. Best results with: exiftool, file, curl, pdfinfo, identify, mediainfo, jq

VERSION="1.0.0"
OUTDIR=""
JSON=0
VERBOSE=0
INPUTS=()

usage() {
  cat <<'EOF'
Usage:
  meta_scraper_cli.sh [options] -i <target> [<target> ...]
  meta_scraper_cli.sh [options] -f <file> [<file> ...]
  meta_scraper_cli.sh [options] -u <url> [<url> ...]

Options:
  -i, --input TARGET     Input target (path or URL). Can be repeated.
  -f, --file FILE        Local file to inspect. Can be repeated.
  -u, --url URL          URL to fetch and inspect. Can be repeated.
  -o, --outdir DIR       Output directory for reports (default: ./meta_out_<timestamp>)
  -j, --json             Also emit JSON report alongside text report
  -v, --verbose          Extra logging
  -h, --help             Show this help
  --version              Show version

Examples:
  ./meta_scraper_cli.sh -i ./sample.pdf
  ./meta_scraper_cli.sh -u https://example.com/file.jpg -o reports -j
  ./meta_scraper_cli.sh -f image.png document.pdf
EOF
}

log() { printf '[*] %s\n' "$*" >&2; }
warn() { printf '[!] %s\n' "$*" >&2; }
die() { printf '[x] %s\n' "$*" >&2; exit 1; }

need_cmd() {
  command -v "$1" >/dev/null 2>&1
}

is_url() {
  [[ "$1" =~ ^https?:// ]]
}

sanitize_name() {
  local s="$1"
  s="${s#http://}"
  s="${s#https://}"
  s="${s//[^A-Za-z0-9._-]/_}"
  printf '%s' "${s:0:180}"
}

sha256_of_file() {
  if need_cmd sha256sum; then
    sha256sum "$1" | awk '{print $1}'
  elif need_cmd shasum; then
    shasum -a 256 "$1" | awk '{print $1}'
  else
    printf 'unavailable'
  fi
}

human_size() {
  local bytes
  bytes=$(stat -c '%s' "$1" 2>/dev/null || wc -c < "$1")
  awk -v b="$bytes" 'function human(x){s="BKBMBGBTBPB"; while(x>=1024&&length(s)>2){x/=1024; s=substr(s,3)}; return sprintf("%.2f %s",x,substr(s,1,2))} BEGIN{print human(b)}'
}

write_text_report_header() {
  local report="$1"
  local target="$2"
  {
    echo "Meta Scraper Report"
    echo "Version: $VERSION"
    echo "Timestamp: $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    echo "Target: $target"
    echo ""
  } > "$report"
}

append_block() {
  local report="$1"
  local title="$2"
  {
    echo "===== $title ====="
    cat
    echo
  } >> "$report"
}

json_escape() {
  if need_cmd python3; then
    python3 - <<'PY' "$1"
import json,sys
print(json.dumps(sys.argv[1]))
PY
  else
    # minimal escape fallback
    local s="$1"
    s=${s//\\/\\\\}
    s=${s//"/\\"}
    s=${s//$'\n'/\\n}
    printf '"%s"' "$s"
  fi
}

collect_file_basics() {
  local path="$1"
  {
    echo "Path: $path"
    echo "Exists: yes"
    echo "Absolute: $(readlink -f "$path" 2>/dev/null || printf '%s' "$path")"
    echo "Size: $(human_size "$path")"
    echo "Bytes: $(stat -c '%s' "$path" 2>/dev/null || wc -c < "$path")"
    echo "MTime: $(stat -c '%y' "$path" 2>/dev/null || true)"
    echo "Owner: $(stat -c '%U:%G' "$path" 2>/dev/null || true)"
    echo "Mode: $(stat -c '%a' "$path" 2>/dev/null || true)"
    echo "SHA256: $(sha256_of_file "$path")"
    if need_cmd file; then
      echo "FileType: $(file -b "$path")"
      echo "MimeType: $(file --mime-type -b "$path" 2>/dev/null || true)"
      echo "Encoding: $(file --mime-encoding -b "$path" 2>/dev/null || true)"
    fi
  }
}

collect_exiftool() {
  local path="$1"
  if need_cmd exiftool; then
    exiftool -a -u -g1 "$path" 2>/dev/null || true
  else
    echo "exiftool: not installed"
  fi
}

collect_pdfinfo() {
  local path="$1"
  if need_cmd pdfinfo; then
    pdfinfo "$path" 2>/dev/null || true
  else
    echo "pdfinfo: not installed"
  fi
}

collect_identify() {
  local path="$1"
  if need_cmd identify; then
    identify -verbose "$path" 2>/dev/null || true
  else
    echo "ImageMagick identify: not installed"
  fi
}

collect_mediainfo() {
  local path="$1"
  if need_cmd mediainfo; then
    mediainfo "$path" 2>/dev/null || true
  else
    echo "mediainfo: not installed"
  fi
}

collect_strings_sample() {
  local path="$1"
  if need_cmd strings; then
    strings -n 8 "$path" 2>/dev/null | head -n 200 || true
  else
    echo "strings: not installed"
  fi
}

collect_http_headers() {
  local url="$1"
  local header_file="$2"
  local body_file="$3"

  if need_cmd curl; then
    local tmp_headers tmp_body
    tmp_headers="$header_file"
    tmp_body="$body_file"
    curl -fsSL -D "$tmp_headers" -o "$tmp_body" "$url"
    {
      echo "URL: $url"
      echo "Final-URL: $(curl -fsSL -o /dev/null -w '%{url_effective}' "$url" 2>/dev/null || printf '%s' "$url")"
      echo "HTTP-Code: $(curl -fsSL -o /dev/null -w '%{http_code}' "$url" 2>/dev/null || true)"
      echo "Content-Type: $(awk 'BEGIN{IGNORECASE=1} /^content-type:/ {sub(/^[^:]+:[[:space:]]*/,"",$0); print; exit}' "$tmp_headers" 2>/dev/null || true)"
      echo "Content-Length: $(awk 'BEGIN{IGNORECASE=1} /^content-length:/ {sub(/^[^:]+:[[:space:]]*/,"",$0); print; exit}' "$tmp_headers" 2>/dev/null || true)"
      echo "Server: $(awk 'BEGIN{IGNORECASE=1} /^server:/ {sub(/^[^:]+:[[:space:]]*/,"",$0); print; exit}' "$tmp_headers" 2>/dev/null || true)"
    }
  else
    die "curl is required for URL inputs"
  fi
}

collect_metadata_for_path() {
  local path="$1"
  local report="$2"
  local mime
  mime=""
  if need_cmd file; then
    mime=$(file --mime-type -b "$path" 2>/dev/null || true)
  fi

  append_block "$report" "BASICS" < <(collect_file_basics "$path")
  append_block "$report" "EXIFTOOL" < <(collect_exiftool "$path")
  append_block "$report" "MIME-DRIVEN DETAILS" < <(
    case "$mime" in
      application/pdf)
        collect_pdfinfo "$path"
        ;;
      image/*)
        collect_identify "$path"
        ;;
      video/*|audio/*)
        collect_mediainfo "$path"
        ;;
      *)
        echo "No specialized extractor selected for MIME type: ${mime:-unknown}"
        collect_strings_sample "$path"
        ;;
    esac
  )
}

emit_json_report() {
  local target="$1"
  local path="$2"
  local headers_file="${3:-}"
  local out_json="$4"

  local sha size mime ftype
  sha=$(sha256_of_file "$path")
  size=$(stat -c '%s' "$path" 2>/dev/null || wc -c < "$path")
  mime=$(need_cmd file && file --mime-type -b "$path" 2>/dev/null || printf 'unknown')
  ftype=$(need_cmd file && file -b "$path" 2>/dev/null || printf 'unknown')

  {
    printf '{\n'
    printf '  "target": %s,\n' "$(json_escape "$target")"
    printf '  "path": %s,\n' "$(json_escape "$path")"
    printf '  "sha256": %s,\n' "$(json_escape "$sha")"
    printf '  "size_bytes": %s,\n' "$size"
    printf '  "mime_type": %s,\n' "$(json_escape "$mime")"
    printf '  "file_type": %s' "$(json_escape "$ftype")"
    if [[ -n "$headers_file" && -f "$headers_file" ]]; then
      printf ',\n  "http_headers": [\n'
      awk 'BEGIN{first=1} {
        gsub(/\\/,"\\\\"); gsub(/"/,"\\\"");
        if (first) { first=0 } else { printf ",\n" }
        printf "    \"%s\"", $0
      } END { if (!first) printf "\n" }' "$headers_file"
      printf '  ]'
    fi
    printf '\n}\n'
  } > "$out_json"
}

process_local_file() {
  local path="$1"
  [[ -f "$path" ]] || { warn "Skipping missing file: $path"; return 0; }

  local base report json_report
  base=$(basename "$path")
  base=$(sanitize_name "$base")
  report="$OUTDIR/${base}.report.txt"
  json_report="$OUTDIR/${base}.report.json"

  write_text_report_header "$report" "$path"
  collect_metadata_for_path "$path" "$report"

  if [[ "$JSON" -eq 1 ]]; then
    emit_json_report "$path" "$path" "" "$json_report"
  fi

  log "Wrote $report"
  [[ "$JSON" -eq 1 ]] && log "Wrote $json_report"
}

process_url() {
  local url="$1"
  local tmpdir headers body report json_report base
  tmpdir=$(mktemp -d)
  headers="$tmpdir/headers.txt"
  body="$tmpdir/body.bin"
  base=$(sanitize_name "$url")
  report="$OUTDIR/${base}.report.txt"
  json_report="$OUTDIR/${base}.report.json"

  write_text_report_header "$report" "$url"
  append_block "$report" "HTTP HEADERS + FETCH" < <(collect_http_headers "$url" "$headers" "$body")
  collect_metadata_for_path "$body" "$report"

  if [[ "$JSON" -eq 1 ]]; then
    emit_json_report "$url" "$body" "$headers" "$json_report"
  fi

  log "Wrote $report"
  [[ "$JSON" -eq 1 ]] && log "Wrote $json_report"
  rm -rf "$tmpdir"
}

main() {
  local arg
  if [[ $# -eq 0 ]]; then
    usage
    exit 1
  fi

  while [[ $# -gt 0 ]]; do
    arg="$1"
    case "$arg" in
      -i|--input)
        shift
        [[ $# -gt 0 ]] || die "--input requires a value"
        INPUTS+=("$1")
        ;;
      -f|--file)
        shift
        [[ $# -gt 0 ]] || die "--file requires a value"
        INPUTS+=("$1")
        ;;
      -u|--url)
        shift
        [[ $# -gt 0 ]] || die "--url requires a value"
        INPUTS+=("$1")
        ;;
      -o|--outdir)
        shift
        [[ $# -gt 0 ]] || die "--outdir requires a value"
        OUTDIR="$1"
        ;;
      -j|--json)
        JSON=1
        ;;
      -v|--verbose)
        VERBOSE=1
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      --version)
        printf '%s\n' "$VERSION"
        exit 0
        ;;
      --)
        shift
        while [[ $# -gt 0 ]]; do INPUTS+=("$1"); shift; done
        break
        ;;
      *)
        INPUTS+=("$1")
        ;;
    esac
    shift || true
  done

  [[ ${#INPUTS[@]} -gt 0 ]] || die "No inputs provided"

  OUTDIR=${OUTDIR:-"./meta_out_$(date +%Y%m%d_%H%M%S)"}
  mkdir -p "$OUTDIR"

  if [[ "$VERBOSE" -eq 1 ]]; then
    log "Output directory: $OUTDIR"
    for c in curl file exiftool pdfinfo identify mediainfo jq strings; do
      need_cmd "$c" && log "Found dependency: $c" || true
    done
  fi

  local t
  for t in "${INPUTS[@]}"; do
    if is_url "$t"; then
      process_url "$t"
    elif [[ -e "$t" ]]; then
      process_local_file "$t"
    else
      warn "Skipping unknown input: $t"
    fi
  done
}

main "$@"
