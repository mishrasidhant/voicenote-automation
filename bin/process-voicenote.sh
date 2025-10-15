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

# --- CHECK DEPENDENCIES ---
FABRIC_BIN="$HOME/.local/bin/fabric"
command -v whisper-cli >/dev/null || { log_error "whisper-cli not found"; exit 1; }
command -v "$FABRIC_BIN" >/dev/null || { log_error "fabric not found"; exit 1; }

# Sanity check to ensure the file is complete
# TODO : add this if you notice issues with syncthing - delete if not needed
wait_for_complete() {
    local f="$1"
    local size1 size2
    size1=$(stat -c%s "$f")
    sleep 2
    size2=$(stat -c%s "$f")
    [[ "$size1" -eq "$size2" ]]
}


# --- SCRIPT START ---
log_info "============================================================"
log_info "Scanning for new files in $VOICENOTES_IN_DIR"

shopt -s nullglob
FILES=("$VOICENOTES_IN_DIR"/*.{mp3,wav})

if [ ${#FILES[@]} -eq 0 ]; then
    log_info "No new files found in $VOICENOTES_IN_DIR"
    exit 0
fi

log_info "DEBUG: files found: ${FILES[@]}"

for VOICENOTE_FILE in "${FILES[@]}"; do
    [ -d "$VOICENOTE_FILE" ] && continue   # skip directories

    FILENAME=$(basename -- "$VOICENOTE_FILE")

    log_info "Processing file: VOICENOTE_FILE='$VOICENOTE_FILE' FILENAME='$FILENAME'"
    log_info "[$FILENAME] START Processing"

    # # 0. Sanity check to ensure the file is complete
    # wait_for_complete "$VOICENOTE_FILE"

    # 1. Archive the voice note immediately
    TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
    ARCHIVE_FILENAME="${TIMESTAMP}_${FILENAME}"
    cp "$VOICENOTE_FILE" "$VOICENOTES_ARCHIVE_DIR/$ARCHIVE_FILENAME"
    log_info "[$FILENAME] archived to '$VOICENOTES_ARCHIVE_DIR/$ARCHIVE_FILENAME'"

    # 2. Transcribe the audio file with whisper.cpp
    log_info "[$FILENAME] Transcribing using whisper.cpp (model: $WHISPER_MODEL, language: $WHISPER_LANGUAGE) to  $VOICENOTE_FILE..."
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
        log_error "[$FILENAME] Transcription failed or produced no output. Skipping file: $FILENAME."
        # TODO trigger alert!!
        # TODO delete the file? or move to a failed directory?
        continue
    fi
    log_info "[$FILENAME] Transcription successful."
    log_info "[$FILENAME] Raw Transcription: $TRANSCRIPTION"

    # 3. Process with Fabric to create the journal entry
    log_info "[$FILENAME] Processing transcription with Fabric pattern: '$FABRIC_PATTERN'..."
    # log=$("$FABRIC_BIN" -p "$FABRIC_PATTERN" "$TRANSCRIPTION" --dry-run)
    # log_info "Fabric dry-run: $log"
    PROCESSED_ENTRY=$("$FABRIC_BIN" -p "$FABRIC_PATTERN" "$TRANSCRIPTION")

    if [ -z "$PROCESSED_ENTRY" ]; then
        log_error "[$FILENAME] Fabric processing failed or produced no output. Skipping file: $FILENAME."
        # TODO trigger alert!!
        # TODO delete the file? or move to a failed directory?
        continue
    fi

    log_info "[$FILENAME] Fabric processing successful."

    # 4. Format and Append to the Telos journal file
    FILE_TIMESTAMP=$(date -r "$VOICENOTE_FILE" "+%Y-%m-%d %H:%M:%S")
    FINAL_JOURNAL_ENTRY="

## Journal Entry - $FILE_TIMESTAMP

$PROCESSED_ENTRY

---
"
    log_info "[$FILENAME] Appending formatted entry to '$TELOS_JOURNAL_FILE'..."
    echo "$FINAL_JOURNAL_ENTRY" >> "$TELOS_JOURNAL_FILE"
    log_info "[$FILENAME] Journal file updated."

    # 5. Clean up original file (ONLY on full success)
    log_info "[$FILENAME] Workflow completed successfully. Deleting original file: $VOICENOTE_FILE"
    rm "$VOICENOTE_FILE"

    log_info "[$FILENAME] END: Processing finished"
    log_info "----------------------------------------------------"
done

# 5. Commit changes to Git - disabled for now - once fabric process is stable we can re-enable
# log_info "Committing changes to Telos repository at '$TELOS_REPO_DIR'..."
# (
#     cd "$TELOS_REPO_DIR"
#     if ! git pull; then
#         log_error "Git pull failed. Please check repository status. Aborting."
#         exit 1
#     fi
#     git add .
#     git commit -m "Journal: Add voice note entry from $FILE_TIMESTAMP"
#     if ! git push; then
#         log_error "Git push failed. Please check credentials and remote status. Aborting."
#         exit 1
#     fi
# )
# log_info "Git commit and push successful."

log_info "END: All files processed."
log_info "============================================================"
