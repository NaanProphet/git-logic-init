#!/bin/bash

# diff_modified_audio.sh — Chunk-level binary diff for Logic Pro audio files
#
# For each git-modified audio file, retrieves the committed (HEAD) version
# via Git LFS and compares it chunk-by-chunk against the working copy.
# Reports whether actual audio data changed or just metadata/overview.
#
# Designed for use with: https://github.com/NaanProphet/git-logic-init
#
# Usage:
#   ./diff_modified_audio.sh                # Diff git-modified audio files
#   ./diff_modified_audio.sh --all          # Diff ALL audio files in .git_store_meta

SCRIPT_NAME="$(basename "$0")"
SCOPE_MODE="modified"  # default: only git-modified files

# Audio file extensions to check
AUDIO_EXTENSIONS=("wav" "aif" "aiff" "mp3" "m4a" "alac" "aifc" "au")

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --all)
            SCOPE_MODE="all"
            shift
            ;;
        --help|-h)
            echo "Usage: $SCRIPT_NAME [OPTIONS]"
            echo ""
            echo "Scope:"
            echo "  (default)                  Only diff audio files with unstaged git changes."
            echo "                             Runs git diff --name-only to determine which files."
            echo "  --all                      Diff ALL audio files listed in .git_store_meta."
            echo ""
            echo "For each file, retrieves the committed version via Git LFS and compares"
            echo "chunk-by-chunk against the working copy."
            echo ""
            echo "Supported formats: WAV (RIFF), AIFF (FORM)"
            echo ""
            echo "Output:"
            echo "  For each chunk in the file, reports whether it changed."
            echo "  The audio data chunk (SSND for AIFF, data for WAV) is highlighted"
            echo "  to distinguish real audio changes from metadata-only changes."
            echo ""
            echo "Verdicts:"
            echo "  IDENTICAL         — file has not changed at all"
            echo "  METADATA ONLY     — only non-audio chunks changed (e.g., LGWV overview)"
            echo "  AUDIO CHANGED     — actual audio sample data differs"
            echo "  SIZE CHANGED      — file size differs (structural change)"
            echo ""
            echo "Examples:"
            echo "  $SCRIPT_NAME                  # Diff git-modified audio files"
            echo "  $SCRIPT_NAME --all            # Diff all audio files"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Check prerequisites
if [[ ! -f ".git_store_meta" ]]; then
    echo "Error: .git_store_meta not found in current directory"
    exit 1
fi

if ! command -v python3 &> /dev/null; then
    echo "Error: python3 is required but not installed"
    exit 1
fi

if ! command -v git &> /dev/null; then
    echo "Error: git is required but not installed"
    exit 1
fi

# Verify git lfs is available
if ! git lfs version &> /dev/null; then
    echo "Error: git lfs is required but not installed"
    exit 1
fi

# Function to check if a file is an audio file
is_audio_file() {
    local file="$1"
    local extension="${file##*.}"
    extension=$(echo "$extension" | tr '[:upper:]' '[:lower:]')

    for ext in "${AUDIO_EXTENSIONS[@]}"; do
        if [[ "$extension" == "$ext" ]]; then
            return 0
        fi
    done
    return 1
}

# ============================================================================
# Main
# ============================================================================

# Build list of files to process
modified_files_list=""
if [[ "$SCOPE_MODE" == "modified" ]]; then
    echo "This script will run 'git diff --name-only' to find modified files."
    read -p "Continue? (y/n) " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Aborted."
        exit 0
    fi

    echo ""
    echo "Running: git diff --name-only"
    modified_files_list=$(git diff --name-only 2>/dev/null)

    modified_count=$(echo "$modified_files_list" | grep -c '[^[:space:]]')
    echo "Found $modified_count modified file(s) in git"
    echo ""

    if [[ $modified_count -eq 0 ]]; then
        echo "No modified files found. Nothing to diff."
        echo "Use --all to diff all audio files in .git_store_meta."
        exit 0
    fi

    echo "Diffing modified audio files..."
else
    echo "Diffing ALL audio files in .git_store_meta..."
fi
echo "============================================"

# Extract audio files from .git_store_meta
audio_files=()
while IFS=$'\t' read -r filepath filetype timestamp; do
    # Skip header and comment lines
    if [[ "$filepath" == "#"* ]] || [[ "$filepath" == "<file>" ]] || [[ -z "$filepath" ]]; then
        continue
    fi

    # Check if it's an audio file and exists
    if is_audio_file "$filepath" && [[ -f "$filepath" ]]; then
        if [[ "$SCOPE_MODE" == "modified" ]]; then
            if echo "$modified_files_list" | grep -qxF "$filepath"; then
                audio_files+=("$filepath")
            fi
        else
            audio_files+=("$filepath")
        fi
    fi
done < .git_store_meta

echo "Found ${#audio_files[@]} audio files to diff"
echo ""

if [[ ${#audio_files[@]} -eq 0 ]]; then
    echo "No audio files to diff."
    exit 0
fi

# Process each file
audio_changed_files=()
metadata_only_files=()
identical_files=()
error_files=()

tmpdir=$(mktemp -d)
trap "rm -rf $tmpdir" EXIT

for filepath in "${audio_files[@]}"; do
    echo "Comparing $filepath..."

    # Retrieve committed version via LFS smudge
    tmp_original="$tmpdir/original"
    git show HEAD:"$filepath" 2>/dev/null | git lfs smudge > "$tmp_original" 2>/dev/null

    if [[ ! -s "$tmp_original" ]]; then
        echo "    ❌ ERROR: Could not retrieve committed version (new file or LFS issue)"
        error_files+=("$filepath")
        echo ""
        continue
    fi

    # Run chunk comparison
    output=$(python3 - "$filepath" "$tmp_original" << 'PYTHON_SCRIPT'
import struct
import sys
import os
from datetime import datetime, timezone

current_path = sys.argv[1]
original_path = sys.argv[2]

def read_file(path):
    with open(path, 'rb') as f:
        return f.read()

def parse_chunks_riff(data):
    if len(data) < 12:
        return None, "File too small for RIFF"
    header = data[0:4]
    if header not in (b'RIFF', b'RF64', b'BW64'):
        return None, "Not a RIFF file"
    chunks = []
    pos = 12
    while pos + 8 <= len(data):
        chunk_id = data[pos:pos+4]
        try:
            chunk_id_str = chunk_id.decode('ascii', errors='replace')
        except:
            chunk_id_str = repr(chunk_id)
        chunk_size = struct.unpack('<I', data[pos+4:pos+8])[0]
        chunk_end = pos + 8 + chunk_size
        if chunk_end > len(data):
            chunk_data = data[pos+8:]
        else:
            chunk_data = data[pos+8:chunk_end]
        chunks.append((chunk_id_str, pos, chunk_size, chunk_data))
        pos = chunk_end
        if pos % 2 != 0:
            pos += 1
    return chunks, None

def parse_chunks_aiff(data):
    if len(data) < 12:
        return None, "File too small for AIFF"
    header = data[0:4]
    if header != b'FORM':
        return None, "Not an AIFF file"
    chunks = []
    pos = 12
    while pos + 8 <= len(data):
        chunk_id = data[pos:pos+4]
        try:
            chunk_id_str = chunk_id.decode('ascii', errors='replace')
        except:
            chunk_id_str = repr(chunk_id)
        chunk_size = struct.unpack('>I', data[pos+4:pos+8])[0]
        chunk_end = pos + 8 + chunk_size
        if chunk_end > len(data):
            chunk_data = data[pos+8:]
        else:
            chunk_data = data[pos+8:chunk_end]
        chunks.append((chunk_id_str, pos, chunk_size, chunk_data))
        pos = chunk_end
        if pos % 2 != 0:
            pos += 1
    return chunks, None

def format_size(size):
    if size < 1024:
        return f"{size} bytes"
    elif size < 1024 * 1024:
        return f"{size:,} bytes ({size/1024:.1f} KB)"
    else:
        return f"{size:,} bytes ({size/(1024*1024):.1f} MB)"

def describe_lgwv_diff(orig_data, curr_data, is_wav):
    details = []
    if len(orig_data) >= 8 and len(curr_data) >= 8:
        if is_wav:
            orig_ts = struct.unpack('<I', orig_data[4:8])[0]
            curr_ts = struct.unpack('<I', curr_data[4:8])[0]
        else:
            orig_ts = struct.unpack('>I', orig_data[4:8])[0]
            curr_ts = struct.unpack('>I', curr_data[4:8])[0]

        if orig_ts != curr_ts:
            mac_epoch_offset = (datetime(1904, 1, 1, tzinfo=timezone.utc) -
                                datetime(1970, 1, 1, tzinfo=timezone.utc)).total_seconds()
            diff_seconds = curr_ts - orig_ts
            diff_hours = diff_seconds / 3600
            try:
                orig_dt = datetime.fromtimestamp(orig_ts + mac_epoch_offset, tz=timezone.utc)
                curr_dt = datetime.fromtimestamp(curr_ts + mac_epoch_offset, tz=timezone.utc)
                details.append(f"timestamp shifted by {diff_seconds:+d}s ({diff_hours:+.1f}h)")
                details.append(f"  committed:  {orig_dt.strftime('%Y-%m-%d %H:%M:%S UTC')}")
                details.append(f"  working:    {curr_dt.strftime('%Y-%m-%d %H:%M:%S UTC')}")
            except:
                details.append(f"timestamp shifted by {diff_seconds:+d}s ({diff_hours:+.1f}h)")

    if len(orig_data) >= 8 and len(curr_data) >= 8:
        orig_overview = orig_data[8:]
        curr_overview = curr_data[8:]
        if orig_overview != curr_overview:
            details.append("overview waveform data also changed")

    return details

def diff_byte_ranges(orig_data, curr_data):
    min_len = min(len(orig_data), len(curr_data))
    changed_count = 0
    for i in range(min_len):
        if orig_data[i] != curr_data[i]:
            changed_count += 1
    if len(orig_data) != len(curr_data):
        changed_count += abs(len(orig_data) - len(curr_data))
    return changed_count

AUDIO_DATA_CHUNKS = {'SSND', 'data'}

try:
    current_data = read_file(current_path)
    original_data = read_file(original_path)
except Exception as e:
    print(f"    ERROR: Could not read files: {e}")
    print("VERDICT:ERROR")
    sys.exit(0)

if current_data == original_data:
    print("    ✅ IDENTICAL — no changes detected")
    print("VERDICT:IDENTICAL")
    sys.exit(0)

curr_size = len(current_data)
orig_size = len(original_data)
if curr_size != orig_size:
    diff = curr_size - orig_size
    print(f"    File size: {format_size(orig_size)} → {format_size(curr_size)} ({diff:+d} bytes)")
else:
    print(f"    File size: {format_size(curr_size)} (unchanged)")

is_wav = False
is_aiff = False
if len(current_data) >= 4:
    hdr = current_data[:4]
    if hdr in (b'RIFF', b'RF64', b'BW64'):
        is_wav = True
    elif hdr == b'FORM':
        is_aiff = True

if not is_wav and not is_aiff:
    changed = diff_byte_ranges(original_data, current_data)
    print(f"    Unknown format — {changed:,} bytes differ")
    print("VERDICT:UNKNOWN")
    sys.exit(0)

format_name = "WAV" if is_wav else "AIFF"
parser = parse_chunks_riff if is_wav else parse_chunks_aiff

orig_chunks, err = parser(original_data)
if err:
    print(f"    ERROR parsing committed version: {err}")
    print("VERDICT:ERROR")
    sys.exit(0)

curr_chunks, err = parser(current_data)
if err:
    print(f"    ERROR parsing working version: {err}")
    print("VERDICT:ERROR")
    sys.exit(0)

orig_map = {}
for chunk in orig_chunks:
    cid = chunk[0]
    orig_map.setdefault(cid, []).append(chunk)

curr_map = {}
for chunk in curr_chunks:
    cid = chunk[0]
    curr_map.setdefault(cid, []).append(chunk)

all_chunk_ids = list(dict.fromkeys(
    [c[0] for c in orig_chunks] + [c[0] for c in curr_chunks]
))

audio_changed = False
metadata_changed = False

print(f"    Format: {format_name}")
print(f"    Chunks:")

for cid in all_chunk_ids:
    orig_list = orig_map.get(cid, [])
    curr_list = curr_map.get(cid, [])

    is_audio = cid.strip() in AUDIO_DATA_CHUNKS
    is_lgwv = cid.strip() == 'LGWV'
    label = " ← audio data" if is_audio else ""

    if len(orig_list) == 0:
        for c in curr_list:
            print(f"      {cid:6s} ({format_size(c[2])})  ➕ ADDED{label}")
            if is_audio:
                audio_changed = True
            else:
                metadata_changed = True
    elif len(curr_list) == 0:
        for c in orig_list:
            print(f"      {cid:6s} ({format_size(c[2])})  ➖ REMOVED{label}")
            if is_audio:
                audio_changed = True
            else:
                metadata_changed = True
    else:
        for i in range(max(len(orig_list), len(curr_list))):
            if i >= len(orig_list):
                c = curr_list[i]
                print(f"      {cid:6s} ({format_size(c[2])})  ➕ ADDED{label}")
                if is_audio:
                    audio_changed = True
                else:
                    metadata_changed = True
            elif i >= len(curr_list):
                c = orig_list[i]
                print(f"      {cid:6s} ({format_size(c[2])})  ➖ REMOVED{label}")
                if is_audio:
                    audio_changed = True
                else:
                    metadata_changed = True
            else:
                o = orig_list[i]
                c = curr_list[i]
                if o[3] == c[3]:
                    print(f"      {cid:6s} ({format_size(c[2])})  ✅ unchanged{label}")
                else:
                    changed_bytes = diff_byte_ranges(o[3], c[3])
                    size_note = ""
                    if o[2] != c[2]:
                        size_note = f", size {o[2]:,} → {c[2]:,}"
                    print(f"      {cid:6s} ({format_size(c[2])})  ❌ changed ({changed_bytes:,} bytes differ{size_note}){label}")

                    if is_lgwv:
                        lgwv_details = describe_lgwv_diff(o[3], c[3], is_wav)
                        for detail in lgwv_details:
                            print(f"             {detail}")

                    if is_audio:
                        audio_changed = True
                    else:
                        metadata_changed = True

print()
if audio_changed:
    print("    🔴 VERDICT: AUDIO CHANGED — actual audio sample data differs")
    print("VERDICT:AUDIO_CHANGED")
elif metadata_changed:
    print("    🟢 VERDICT: METADATA ONLY — audio data is identical, safe to revert")
    print("VERDICT:METADATA_ONLY")
else:
    print("    ✅ VERDICT: IDENTICAL")
    print("VERDICT:IDENTICAL")
PYTHON_SCRIPT
)

    # Print the output (everything except the VERDICT: line)
    echo "$output" | grep -v "^VERDICT:"

    # Parse verdict for summary
    verdict=$(echo "$output" | grep "^VERDICT:" | tail -1 | cut -d: -f2)
    case "$verdict" in
        IDENTICAL)
            identical_files+=("$filepath")
            ;;
        METADATA_ONLY)
            metadata_only_files+=("$filepath")
            ;;
        AUDIO_CHANGED)
            audio_changed_files+=("$filepath")
            ;;
        *)
            error_files+=("$filepath")
            ;;
    esac

    echo ""
done

# Summary
echo "============================================"
echo "SUMMARY:"
echo "========"
echo "✅ Identical: ${#identical_files[@]}"
echo "🟢 Metadata only (safe to revert): ${#metadata_only_files[@]}"
echo "🔴 Audio changed: ${#audio_changed_files[@]}"

if [[ ${#error_files[@]} -gt 0 ]]; then
    echo "❌ Errors: ${#error_files[@]}"
fi

if [[ ${#metadata_only_files[@]} -gt 0 ]]; then
    echo ""
    echo "Files safe to revert (metadata only):"
    for f in "${metadata_only_files[@]}"; do
        echo "  $f"
    done
    echo ""
    echo "To revert these files:"
    echo "  git checkout HEAD -- <file>"
fi

if [[ ${#audio_changed_files[@]} -gt 0 ]]; then
    echo ""
    echo "Files with actual audio changes (DO NOT blindly revert):"
    for f in "${audio_changed_files[@]}"; do
        echo "  $f"
    done
fi

# Cleanup handled by trap
