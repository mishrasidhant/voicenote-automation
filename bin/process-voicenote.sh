#!/bin/bash

# Exit immediately if a command exits with a non-zero status.
set -euo pipefail

# --- LOAD CONFIGURATION ---
CONFIG_FILE="$HOME/.config/voicenote-automation/config"
if [ ! -f "$CONFIG_FILE" ]; then
    echo "FATAL: Configuration file not found at $CONFIG_FILE" >&2
    exit 1
fi
source "$CONFIG_FILE"

# --- ARGUMENT CHECK ---
if [ -z "$1" ]; then
    echo "FATAL: No input file provided." >&2
    echo "Usage: $0 /path/to/audio/file" >&2
    exit 1
fi
VOICENOTE_FILE="$1"
FILENAME=$(basename "$VOICENOTE_FILE")

# --- LOGGING SETUP ---
# Ensure log directory exists and redirect all output to the log file
mkdir -p "$LOG_DIR"
exec > >(tee -a "${LOG_DIR}/automation.log") 2>&1

log_info() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] [INFO] $1"
}

log_error() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] [ERROR] $1" >&2
}

# --- SCRIPT START ---
log_info "============================================================"
log_info "START: Processing new file: $FILENAME"

# 1. Archive the voice note immediately
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
ARCHIVE_FILENAME="${TIMESTAMP}_${FILENAME}"
log_info "Archiving to '$VOICENOTES_ARCHIVE_DIR/$ARCHIVE_FILENAME'..."
cp "$VOICENOTE_FILE" "$VOICENOTES_ARCHIVE_DIR/$ARCHIVE_FILENAME"
log_info "Archive successful."

# 2. Transcribe the audio file with whisper.cpp
log_info "Transcribing using whisper.cpp (model: $WHISPER_MODEL, language: $WHISPER_LANGUAGE) to  $VOICENOTE_FILE..."
# The output from whisper.cpp CLI is just the text, which is perfect.
TRANSCRIPTION=$(
    whisper-cli \
        -m "$HOME/.local/share/whisper.cpp/models/ggml-${WHISPER_MODEL}.bin" \
        -f "$VOICENOTE_FILE" \
        -l "$WHISPER_LANGUAGE" \
        --output-txt \
    | grep -v '^note:' | tr '\n' ' ' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
)

if [ -z "$TRANSCRIPTION" ]; then
    log_error "Transcription failed or produced no output. Aborting."
    exit 1
fi
log_info "Transcription successful."
log_info "Raw Transcription: $TRANSCRIPTION"

# 3. Process with Fabric to create the journal entry
#log_info "Processing transcription with Fabric pattern: '$FABRIC_PATTERN'..."
#PROCESSED_ENTRY=$(fabric -p "$FABRIC_PATTERN" "$TRANSCRIPTION")
# PROCESSED_ENTRY="$TRANSCRIPTION"

# if [ -z "$PROCESSED_ENTRY" ]; then
#     log_error "Fabric processing failed or produced no output. Aborting."
#     exit 1
# fi
#log_info "Fabric processing successful."
log_info "Raw transcription processing successful."

# 4. Format and Append to the Telos journal file
FILE_TIMESTAMP=$(date -r "$VOICENOTE_FILE" "+%Y-%m-%d %H:%M:%S")
FINAL_JOURNAL_ENTRY="
## Journal Entry - $FILE_TIMESTAMP

$TRANSCRIPTION

---
"
log_info "Appending formatted entry to '$TELOS_JOURNAL_FILE'..."
echo "$FINAL_JOURNAL_ENTRY" >> "$TELOS_JOURNAL_FILE"
log_info "Journal file updated."

# 5. Commit changes to Git
log_info "Committing changes to Telos repository at '$TELOS_REPO_DIR'..."
(
    cd "$TELOS_REPO_DIR"
    if ! git pull; then
        log_error "Git pull failed. Please check repository status. Aborting."
        exit 1
    fi
    git add .
    git commit -m "Journal: Add voice note entry from $FILE_TIMESTAMP"
    if ! git push; then
        log_error "Git push failed. Please check credentials and remote status. Aborting."
        exit 1
    fi
)
log_info "Git commit and push successful."

# 6. Clean up original file (ONLY on full success)
log_info "Workflow completed successfully. Deleting original file: $VOICENOTE_FILE"
rm "$VOICENOTE_FILE"

log_info "END: Processing finished for $FILENAME."
log_info "============================================================"
