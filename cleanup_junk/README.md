# Junk Cleanup Script for Synology NAS

A robust Bash script to locate and optionally delete common junk files (`.DS_Store`, `Thumbs.db`, `desktop.ini`, Apple Double files, temporary Office files, etc.) across specified directories on a Synology NAS (or any Linux system).  
It supports two modes of operation: **dry-run** (test) and **delete**, and provides detailed reporting along with configurable logging.

## Features

- **Dry-run mode** – shows what would be deleted without touching any file.
- **Delete mode** – permanently removes matching files.
- **Detailed per‑directory and overall report** printed to `stdout` and appended to the log file.
- **Structured logging** – timestamped log entries with `INFO` and `DEBUG` levels.
- **Default log file location** – created in the same directory as the script, with the hostname and timestamp.
- **Automatic log cleanup** – optionally remove log files older than a configurable number of days.
- **Directory exclusions**:
  - `--exclude-system-dirs` – automatically detects and skips all `@`-prefixed system folders in the root of each volume (no need to maintain a static list).
  - `--exclude-dir <DIR>` – manually exclude specific directories (absolute or relative paths, repeatable).
- **Safe file handling** – uses `find -print0` and null‑separated reading to correctly handle filenames with spaces or special characters.
- **Human‑readable sizes** – uses `numfmt` if available, otherwise falls back to raw byte counts.
- **Extensible junk patterns** – easily add or remove patterns inside the script.

## Requirements

- **Bash** ≥ 4 (standard on Synology DSM and most Linux distributions).
- Standard utilities: `find`, `stat`, `rm`, `mktemp`, `tee`, `hostname`, `realpath` (optional).
- Write permission for the log file directory and, in delete mode, for the target directories.

## Installation

1. Copy the script to your preferred location on the Synology NAS, e.g., `/volume1/scripts/cleanup_junk/cleanup_junk.sh`.
2. Make it executable:
   ```bash
   chmod +x /volume1/scripts/cleanup_junk/cleanup_junk.sh
   ```
3. (Optional) Adjust the `JUNK_PATTERNS` array inside the script to match your needs.

## Usage

```bash
/volume1/scripts/cleanup_junk/cleanup_junk.sh [OPTIONS] DIRECTORY [DIRECTORY...]
```

### Options

| Option                  | Description                                                                                                   |
|-------------------------|---------------------------------------------------------------------------------------------------------------|
| `--mode <MODE>`         | Operation mode: `dry-run` (default) or `delete`.                                                              |
| `--log-file <FILE>`     | Path to the log file. Default: `<script_dir>/junk_cleanup_<hostname>_YYYYMMDD_HHMMSS.log`                     |
| `--log-level <LEVEL>`   | Log verbosity: `INFO` (default) or `DEBUG`.                                                                   |
| `--exclude-dir <DIR>`   | Exclude a directory (can be specified multiple times). Both absolute and relative (to target) paths accepted.   |
| `--exclude-system-dirs` | Auto-detect all `@`-prefixed directories in the root of each volume and exclude them from scanning.            |
| `--cleanup-logs [DAYS]` | Delete log files matching `junk_cleanup_*.log` older than DAYS days. If DAYS is `0`, removes all old logs except the one currently being written. Default: 180. |
| `-h, --help`            | Show the help message and exit.                                                                               |

At least one target directory must be provided.

### Examples

```bash
# Dry-run to see what would be deleted under a shared folder
/volume1/scripts/cleanup_junk/cleanup_junk.sh /volume1/homes

# Delete junk files, auto-excluding all system @-folders on volume1
/volume1/scripts/cleanup_junk/cleanup_junk.sh --mode delete --exclude-system-dirs /volume1/

# Delete with DEBUG logging, exclude system dirs, and keep logs for 90 days
/volume1/scripts/cleanup_junk/cleanup_junk.sh --log-level DEBUG --mode delete --exclude-system-dirs /volume1/

# Scan multiple volumes, exclude custom directories in addition to system folders
/volume1/scripts/cleanup_junk/cleanup_junk.sh --mode delete \
    --exclude-system-dirs \
    --exclude-dir /volume2/private \
    --exclude-dir @appstore \
    /volume1 /volume2

# Dry-run with DEBUG logs written to a custom file
/volume1/scripts/cleanup_junk/cleanup_junk.sh --log-level DEBUG --log-file /tmp/debug.log /volume1/music

# Delete junk files and remove ALL old logs except the current one
/volume1/scripts/cleanup_junk/cleanup_junk.sh --mode delete --cleanup-logs 0 /volume1/

# Delete junk files and remove logs older than 30 days (keep last month)
/volume1/scripts/cleanup_junk/cleanup_junk.sh --mode delete --cleanup-logs 30 /volume1/
```

## File Patterns (Default)

The script searches for the following patterns as **regular files**:

- `.DS_Store` – macOS folder metadata.
- `Thumbs.db` – Windows thumbnail cache.
- `desktop.ini` – Windows folder customization file.
- `ehthumbs.db` – Windows Explorer thumbnail database.
- `._*` – Apple Double resource fork files (often left by macOS clients).
- `~$*` – Microsoft Office temporary lock/owner files.

You can modify the `JUNK_PATTERNS` array inside the script to add or remove items.  
All patterns are combined with `-o` (OR) and only regular files are considered.

## How It Works

1. The script traverses each supplied directory using `find`.
2. If `--exclude-system-dirs` is set, it first detects all directories matching `@*` in the root of each target volume and adds them to the exclusion list.
3. For every matched file it records its size and either:
   - prints `Would delete: <path>` (dry-run), or
   - attempts to delete it with `rm -f` and logs success/failure.
4. A per‑directory summary is appended to an in‑memory report.
5. After processing all directories, the full report is printed to `stdout` and duplicated to the log file.
6. If `--cleanup-logs` was specified, old log files are purged before the final report.

## Logging

- The log file contains entries like:
  ```
  [2026-04-15 14:30:02] [INFO ] Junk cleanup started | mode=delete | log_level=INFO
  [2026-04-15 14:30:02] [INFO ] Auto-excluded system directory: /volume1/@tmp
  [2026-04-15 14:30:12] [INFO ] Dir /volume1/homes: found=42 size=123456 bytes
  [2026-04-15 14:30:15] [INFO ] Script finished. total_files=42 total_size=123456 deleted=42 failed=0 reclaimed=123456
  ```
- In `DEBUG` mode, every file path and its size are also logged.
- The log file is **appended**, not overwritten, on each run.

## Report

The script always prints a report to the console. It includes:

- A header with mode and target paths (and exclusion list if any).
- For each scanned directory:
  - List of files that would be / were deleted (or failures).
  - Summary: number of files found, total size, (in delete mode: deleted count, failed count, reclaimed space).
- An overall summary combining all directories.

## Log Cleanup

Use `--cleanup-logs` to automatically remove log files older than a certain number of days (default 180).  
The cleanup targets only files matching `junk_cleanup_*.log` inside the log directory.  
This operation runs **after** processing all directories but before printing the final report, so the current log is not affected.

## Exit Codes

- `0` – Script completed successfully (even if some deletions failed).
- `1` – Invalid arguments, missing directories, or other fatal errors.

## Error Handling

- The script validates all arguments and provided directories.
- If a directory does not exist, it is skipped with a warning in both the report and the log.
- `find` errors (e.g., permission denied) are captured and logged, but do not stop the processing of other directories.
- Deletion failures (e.g., permission denied) are recorded per file and included in the report; the script continues.
- Temporary files are cleaned up on exit (`trap` on `EXIT`).

## License

This script is provided as-is without any warranty. You are free to use, modify, and distribute it.