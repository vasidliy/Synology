#!/bin/bash
#===============================================================================
# Script: cleanup_junk.sh
# Description: Remove common junk files (.DS_Store, Thumbs.db, etc.) on Synology NAS
#              Works in two modes: dry-run (test) and delete.
#              Provides detailed report (console + log) and configurable logging (INFO/DEBUG).
#              Default log file is created in the script's directory and includes hostname.
#              Supports automatic log cleanup and directory exclusions.
#              --exclude-system-dirs now auto-detects all @-directories in volume roots.
# Usage:       cleanup_junk.sh [OPTIONS] DIRECTORY [DIRECTORY...]
#===============================================================================

set -o pipefail

# -----------------------------------------------------------------------------
# Default configuration
# -----------------------------------------------------------------------------
MODE="dry-run"
LOG_LEVEL="INFO"
CLEANUP_DAYS=""                  # if set, old logs will be removed

# Determine script's directory (default log location) and hostname
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)" || SCRIPT_DIR="/tmp"
HOST_NAME=$(hostname 2>/dev/null || uname -n 2>/dev/null || echo "unknown")
LOG_FILE="${SCRIPT_DIR}/junk_cleanup_${HOST_NAME}_$(date +%Y%m%d_%H%M%S).log"

declare -a TARGET_DIRS=()
declare -a EXCLUDE_DIRS=()       # list of directory patterns to skip

# File patterns to delete (regular files only)
JUNK_PATTERNS=(
    -name '.DS_Store'
    -o -name 'Thumbs.db'
    -o -name 'desktop.ini'
    -o -name 'ehthumbs.db'
    -o -name '._*'          # Apple Double resource fork files
    -o -name '~$*'          # Microsoft Office temporary files
)

# -----------------------------------------------------------------------------
# Helper functions
# -----------------------------------------------------------------------------
usage() {
    cat <<EOF
Usage: $0 [OPTIONS] DIRECTORY [DIRECTORY...]

Remove junk files (.DS_Store, Thumbs.db, etc.) from specified directories.

OPTIONS:
  --mode <MODE>          Operation mode: "dry-run" (test, default) or "delete"
  --log-file <FILE>      Path to log file
                         (default: <script dir>/junk_cleanup_<hostname>_<datetime>.log)
  --log-level <LEVEL>    Log verbosity: INFO (default) or DEBUG
  --exclude-dir <DIR>    Exclude a directory (can be repeated). Relative to target or absolute.
  --exclude-system-dirs  Auto-exclude all system @-directories in the root of each volume
  --cleanup-logs [DAYS]  Delete log files older than DAYS (default: 180) in the log directory
  -h, --help             Show this help and exit

EXAMPLES:
  $0 /volume1/homes
  $0 --mode delete --exclude-system-dirs /volume1 /volume2
  $0 --mode delete --exclude-dir @tmp --exclude-dir /volume3/private --cleanup-logs 90 /volume1
EOF
    exit 0
}

die() {
    echo "ERROR: $*" >&2
    exit 1
}

# Write log message to LOG_FILE if level is appropriate
log() {
    local level="$1"; shift
    local msg="$*"
    local timestamp
    timestamp=$(date +'%Y-%m-%d %H:%M:%S') || true

    if [[ "$LOG_LEVEL" == "DEBUG" || ( "$LOG_LEVEL" == "INFO" && "$level" != "DEBUG" ) ]]; then
        printf '[%s] [%-5s] %s\n' "$timestamp" "$level" "$msg" >> "$LOG_FILE"
    fi
}

# Cleanup temporary files on exit
cleanup_tempfiles() {
    rm -f "$REPORT_FILE" "$FIND_ERR_FILE"
}
trap cleanup_tempfiles EXIT

# Clean up old log files
perform_log_cleanup() {
    if [[ -z "$CLEANUP_DAYS" ]]; then
        return
    fi
    local log_dir
    log_dir=$(dirname "$LOG_FILE")
    log INFO "Log cleanup: removing log files older than $CLEANUP_DAYS days in $log_dir"
    local deleted_count=0

    if [[ "$CLEANUP_DAYS" -eq 0 ]]; then
        # Special case: delete all matching logs except the current one
        while IFS= read -r -d '' old_log; do
            if [[ "$old_log" != "$LOG_FILE" ]]; then
                if rm -f -- "$old_log" 2>/dev/null; then
                    log INFO "Removed old log: $old_log"
                    ((deleted_count++))
                else
                    log INFO "Failed to remove old log: $old_log"
                fi
            fi
        done < <(find "$log_dir" -maxdepth 1 -type f -name "junk_cleanup_*.log" -print0 2>/dev/null)
    else
        # Normal case: delete files older than CLEANUP_DAYS days
        while IFS= read -r -d '' old_log; do
            if rm -f -- "$old_log" 2>/dev/null; then
                log INFO "Removed old log: $old_log"
                ((deleted_count++))
            else
                log INFO "Failed to remove old log: $old_log"
            fi
        done < <(find "$log_dir" -maxdepth 1 -type f -name "junk_cleanup_*.log" -mtime +"$CLEANUP_DAYS" -print0 2>/dev/null)
    fi

    log INFO "Log cleanup completed: $deleted_count file(s) removed."
}

# -----------------------------------------------------------------------------
# Sanity checks for required commands
# -----------------------------------------------------------------------------
for cmd in find stat rm mktemp tee hostname; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        die "Required command '$cmd' not found."
    fi
done

# -----------------------------------------------------------------------------
# Main program
# -----------------------------------------------------------------------------
main() {
    # ---- Argument parsing ---------------------------------------------------
    local auto_exclude_system=false

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --mode)
                MODE="$2"
                shift 2
                ;;
            --log-file)
                LOG_FILE="$2"
                shift 2
                ;;
            --log-level)
                LOG_LEVEL="$2"
                shift 2
                ;;
            --exclude-dir)
                EXCLUDE_DIRS+=("$2")
                shift 2
                ;;
            --exclude-system-dirs)
                auto_exclude_system=true
                shift
                ;;
            --cleanup-logs)
                if [[ $# -gt 1 && "$2" =~ ^[0-9]+$ ]]; then
                    CLEANUP_DAYS="$2"
                    shift 2
                else
                    CLEANUP_DAYS=180
                    shift
                fi
                ;;
            -h|--help)
                usage
                ;;
            --)
                shift
                break
                ;;
            -*)
                die "Unknown option: $1"
                ;;
            *)
                TARGET_DIRS+=("$1")
                shift
                ;;
        esac
    done
    # Collect remaining positional arguments (after --)
    while [[ $# -gt 0 ]]; do
        TARGET_DIRS+=("$1")
        shift
    done

    # ---- Validation ---------------------------------------------------------
    if [[ ${#TARGET_DIRS[@]} -eq 0 ]]; then
        die "No target directories provided. See --help."
    fi

    if [[ "$MODE" != "dry-run" && "$MODE" != "delete" ]]; then
        die "Invalid mode: '$MODE'. Must be 'dry-run' or 'delete'."
    fi

    if [[ "$LOG_LEVEL" != "INFO" && "$LOG_LEVEL" != "DEBUG" ]]; then
        die "Invalid log level: '$LOG_LEVEL'. Must be 'INFO' or 'DEBUG'."
    fi

    # ---- Prepare logging ----------------------------------------------------
    LOG_DIR=$(dirname "$LOG_FILE")
    mkdir -p "$LOG_DIR" || die "Cannot create log directory: $LOG_DIR"
    if ! touch "$LOG_FILE" 2>/dev/null; then
        die "Cannot write to log file: $LOG_FILE"
    fi

    log INFO "Junk cleanup started | mode=$MODE | log_level=$LOG_LEVEL"
    log DEBUG "Targets: ${TARGET_DIRS[*]}"

    # ---- Auto-detect system directories if requested ------------------------
    if [[ "$auto_exclude_system" == true ]]; then
        for dir in "${TARGET_DIRS[@]}"; do
            # Search for @-directories only in the immediate root of this directory
            while IFS= read -r -d '' sys_dir; do
                EXCLUDE_DIRS+=("$sys_dir")
                log INFO "Auto-excluded system directory: $sys_dir"
            done < <(find "$dir" -maxdepth 1 -type d -name '@*' -print0 2>/dev/null)
        done
    fi

    [[ ${#EXCLUDE_DIRS[@]} -gt 0 ]] && log INFO "Final excluded directories: ${EXCLUDE_DIRS[*]}"

    # ---- Prepare temporary report file -------------------------------------
    REPORT_FILE=$(mktemp) || die "Failed to create temporary report file"
    FIND_ERR_FILE=$(mktemp) || die "Failed to create temporary find error file"
    log DEBUG "Report temp file: $REPORT_FILE"

    # ---- Global counters ----------------------------------------------------
    total_files=0
    total_size=0
    total_deleted=0
    total_failed=0
    total_deleted_size=0

    # ---- Process each target directory -------------------------------------
    for dir in "${TARGET_DIRS[@]}"; do
        if [[ ! -d "$dir" ]]; then
            log INFO "Skipping non-directory: $dir"
            echo "### WARNING: $dir is not a directory – skipped ###" >> "$REPORT_FILE"
            continue
        fi

        dir_real=$(realpath "$dir" 2>/dev/null || echo "$dir")
        log INFO "Processing directory: $dir_real"
        echo "### Directory: $dir_real ###" >> "$REPORT_FILE"

        # Build the find expression array with exclusions
        local -a find_expr=("$dir")
        local normalized_dir="${dir%/}"
        [[ -z "$normalized_dir" ]] && normalized_dir="/"
        for excl in "${EXCLUDE_DIRS[@]}"; do
            excl="${excl%/}"
            local excl_path=""
            if [[ "$excl" == /* ]]; then
                excl_path="$excl"
                # Only apply if it's under the current target directory
                if [[ "$excl_path" == "$normalized_dir"/* || "$excl_path" == "$normalized_dir" ]]; then
                    find_expr+=(-path "$excl_path" -prune -o)
                fi
            else
                excl_path="$normalized_dir/$excl"
                find_expr+=(-path "$excl_path" -prune -o)
            fi
        done
        # Add the main search condition
        find_expr+=(-type f \( "${JUNK_PATTERNS[@]}" \) -print0)

        log DEBUG "Running: find ${find_expr[*]}"

        # Per-directory counters
        dir_files=0
        dir_size=0
        dir_deleted=0
        dir_failed=0
        dir_deleted_size=0

        # Execute find and process files
        while IFS= read -r -d '' file; do
            ((dir_files++))
            size=$(stat -c %s -- "$file" 2>/dev/null || echo 0)
            ((dir_size += size))

            if [[ "$MODE" == "dry-run" ]]; then
                printf 'Would delete: %s\n' "$file" >> "$REPORT_FILE"
                log DEBUG "Would delete: $file ($size bytes)"
            else
                if rm -f -- "$file" 2>/dev/null; then
                    printf 'Deleted: %s\n' "$file" >> "$REPORT_FILE"
                    log DEBUG "Deleted: $file ($size bytes)"
                    ((dir_deleted++))
                    ((dir_deleted_size += size))
                else
                    printf 'FAILED to delete: %s\n' "$file" >> "$REPORT_FILE"
                    log INFO "Failed to delete: $file"
                    ((dir_failed++))
                fi
            fi
        done < <(find "${find_expr[@]}" 2>"$FIND_ERR_FILE")

        # Log any errors from the find command itself
        if [[ -s "$FIND_ERR_FILE" ]]; then
            find_errors=$(<"$FIND_ERR_FILE")
            log INFO "Find errors in $dir_real: $find_errors"
            : > "$FIND_ERR_FILE"   # truncate for next iteration
        fi

        # Human‑readable size helper (numfmt if available)
        if command -v numfmt >/dev/null 2>&1; then
            human_size=$(numfmt --to=iec-i --suffix=B "$dir_size")
            human_reclaimed=$(numfmt --to=iec-i --suffix=B "$dir_deleted_size")
        else
            human_size="${dir_size} B"
            human_reclaimed="${dir_deleted_size} B"
        fi

        # Directory summary in report
        {
            echo "--- Summary for $dir_real ---"
            echo "Files found : $dir_files"
            echo "Total size  : $human_size"
            if [[ "$MODE" == "delete" ]]; then
                echo "Deleted     : $dir_deleted files ($human_reclaimed)"
                echo "Failed      : $dir_failed"
            fi
            echo ""
        } >> "$REPORT_FILE"

        log INFO "Dir $dir_real: found=$dir_files size=$dir_size bytes"
        [[ "$MODE" == "delete" ]] && log INFO "Deleted=$dir_deleted failed=$dir_failed reclaimed=$dir_deleted_size bytes"

        # Accumulate global stats
        ((total_files += dir_files))
        ((total_size += dir_size))
        ((total_deleted += dir_deleted))
        ((total_failed += dir_failed))
        ((total_deleted_size += dir_deleted_size))
    done

    # ---- Log cleanup (before final report) ---------------------------------
    perform_log_cleanup

    # ---- Final report (printed to stdout AND appended to log) ---------------
    {
        echo ""
        echo "========================================="
        echo "         JUNK CLEANUP REPORT"
        echo "========================================="
        echo "Mode : $MODE"
        echo "Paths: ${TARGET_DIRS[*]}"
        [[ ${#EXCLUDE_DIRS[@]} -gt 0 ]] && echo "Excluded: ${EXCLUDE_DIRS[*]}"
        echo ""
        cat "$REPORT_FILE"

        if command -v numfmt >/dev/null 2>&1; then
            total_human=$(numfmt --to=iec-i --suffix=B "$total_size")
            reclaimed_human=$(numfmt --to=iec-i --suffix=B "$total_deleted_size")
        else
            total_human="${total_size} B"
            reclaimed_human="${total_deleted_size} B"
        fi

        echo "=== Overall Summary ==="
        echo "Total files found    : $total_files"
        echo "Total size           : $total_human"
        if [[ "$MODE" == "delete" ]]; then
            echo "Successfully deleted : $total_deleted files"
            echo "Failed deletions     : $total_failed files"
            echo "Reclaimed space      : $reclaimed_human"
        fi
    } | tee -a "$LOG_FILE"

    log INFO "Script finished. total_files=$total_files total_size=$total_size deleted=$total_deleted failed=$total_failed reclaimed=$total_deleted_size"
    [[ "$MODE" == "delete" && $total_failed -gt 0 ]] && log INFO "Some files could not be deleted – check permissions."
}

# -----------------------------------------------------------------------------
# Entry point
# -----------------------------------------------------------------------------
main "$@"