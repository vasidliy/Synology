#!/usr/bin/env bash
# update_clamav.sh - ClamAV database updater for Synology Antivirus Essential

set -euo pipefail

# ---------- Configuration ----------
SCRIPT_BASE_DIR="/volume1/scripts"
UPDATER_DIR="${SCRIPT_BASE_DIR}/clamav_updater"
TMP_DIR="${UPDATER_DIR}/temp"
DEST_DIR="/var/packages/AntiVirus/target/engine/clamav/var/lib"
BASE_URL="https://packages.microsoft.com/clamav"
FILES=("bytecode.cvd" "daily.cvd" "main.cvd")
MAX_RETRIES=3
RETRY_DELAY=5
LOG_FILE="${UPDATER_DIR}/update_clamav.log"

# ---------- Functions ----------
log() {
    local message="[$(date '+%Y-%m-%d %H:%M:%S')] $*"
    echo "$message"
    # Also log to file if LOG_FILE is set
    if [ -n "${LOG_FILE}" ]; then
        echo "$message" >> "${LOG_FILE}"
    fi
}

cleanup() {
    log "Cleaning temporary files..."
    for file in "${FILES[@]}"; do
        rm -f "${TMP_DIR}/${file}"
    done
}

# Error handler
error_exit() {
    log "ERROR: $1"
    cleanup
    exit 1
}

# Create directory if it doesn't exist
ensure_dir() {
    if [ ! -d "$1" ]; then
        mkdir -p "$1" || error_exit "Cannot create directory: $1"
        log "Created directory: $1"
    fi
}

# Download with retry logic
download_file() {
    local file="$1"
    local url="${BASE_URL}/${file}"
    local attempt=1
    
    while [ $attempt -le $MAX_RETRIES ]; do
        log "Downloading ${file} (attempt $attempt/$MAX_RETRIES)..."
        if wget --quiet --tries=1 --timeout=30 -O "${TMP_DIR}/${file}" "$url"; then
            # Verify file is not empty
            if [ -s "${TMP_DIR}/${file}" ]; then
                log "Successfully downloaded: ${file}"
                return 0
            else
                log "Warning: Downloaded file is empty: ${file}"
            fi
        fi
        
        if [ $attempt -lt $MAX_RETRIES ]; then
            log "Retrying in ${RETRY_DELAY} seconds..."
            sleep $RETRY_DELAY
        fi
        ((attempt++))
    done
    
    error_exit "Failed to download ${file} after ${MAX_RETRIES} attempts"
}

download_updates() {
    log "Changing to temporary directory: ${TMP_DIR}"
    ensure_dir "$TMP_DIR"
    cd "${TMP_DIR}" || error_exit "Cannot access directory: ${TMP_DIR}"
    
    for file in "${FILES[@]}"; do
        download_file "$file"
    done
}

install_updates() {
    log "Copying updates to: ${DEST_DIR}"
    ensure_dir "$DEST_DIR"
    
    for file in "${FILES[@]}"; do
        if cp -f "${TMP_DIR}/${file}" "${DEST_DIR}/"; then
            log "Successfully copied: ${file}"
        else
            error_exit "Failed to copy ${file}"
        fi
    done
    
    # Set appropriate permissions (adjust if needed)
    chmod 644 "${DEST_DIR}"/*.cvd 2>/dev/null || true
}

# ---------- Main Execution ----------
log "=== Starting ClamAV database update ==="

# Create updater directory if it doesn't exist
ensure_dir "$UPDATER_DIR"
ensure_dir "$TMP_DIR"

# Verify destination is writable
if [ ! -w "$DEST_DIR" ]; then
    error_exit "Destination directory is not writable: ${DEST_DIR}"
fi

# Set trap for cleanup on script exit
trap cleanup EXIT

download_updates
install_updates

log "=== ClamAV database update completed successfully ==="