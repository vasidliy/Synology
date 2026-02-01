# ClamAV Database Updater for Synology

This script automates the manual update of ClamAV virus databases for Synology Antivirus Essential package.

## Overview

Synology's Antivirus Essential uses ClamAV as its scanning engine. However, the automatic update feature may not always work reliably. This script manually downloads the latest virus definitions from Microsoft's ClamAV repository and installs them to the correct location on your Synology NAS.

## Directory Structure

First, create a shared folder for all scripts on your Synology, then this script will create its own subdirectory:

/volume1/scripts/ # Shared folder for all scripts (create manually)  
└── clamav_updater/ # Isolated directory for this updater (auto-created)  
├── update_clamav.sh # Main script file  
├── update_clamav.log # Log file (auto-created)  
├── temp/ # Temporary download directory (auto-created)  
├─── bytecode.cvd  
├───daily.cvd  
└─── main.cvd

## Prerequisites

1. Synology NAS with Antivirus Essential package installed
2. Bash shell environment
3. `wget` utility (usually pre-installed on Synology)
4. Sufficient permissions to write to the target directory

## Installation

### Step 1: Create Shared Scripts Folder

1. Go to **Control Panel** > **Shared Folder** and click **Create** > **Create Shared Folder**.
	Create a new shared folder named `scripts`

### Step 2: Create the ClamAV Updater Subfolder

1. Open the newly created `scripts` folder
2. Create another folder inside it named `clamav_updater`:
   - Right-click in the `scripts` folder → **Create** → **Create Folder**
   - Enter the name: `clamav_updater`
   - Click **OK**
### Step 3: Upload the Script

1. Download the `update_clamav.sh` script to your local computer
2. In File Station, navigate to `/volume1/scripts/clamav_updater/`
3. Upload the script file:
   - Click the **Upload** button → **Upload - Overwrite** or drag and drop the file
   - Select the `update_clamav.sh` file from your local computer
   - Wait for the upload to complete


## Configuration

The script uses the following default configuration:

|Variable|Default Value|Description|
|---|---|---|
|`SCRIPT_BASE_DIR`|`/volume1/scripts`|Base directory for all scripts|
|`UPDATER_DIR`|`/volume1/scripts/clamav_updater`|Isolated directory for this updater|
|`TMP_DIR`|`/volume1/scripts/clamav_updater/temp`|Temporary directory for downloads|
|`DEST_DIR`|`/var/packages/AntiVirus/target/engine/clamav/var/lib`|ClamAV database directory|
|`MAX_RETRIES`|`3`|Maximum download retry attempts|
|`RETRY_DELAY`|`5`|Delay between retries (seconds)|
|`LOG_FILE`|`/volume1/scripts/clamav_updater/update_clamav.log`|Log file location|

## Usage

### Manual Execution

```bash
sudo /volume1/scripts/clamav_updater/update_clamav.sh
```

### Schedule with Task Scheduler

1. Open **Control Panel** → **Task Scheduler**

2. Click **Create** → **Scheduled Task** → **User-defined script**

3. Configure:
    - **Task**: `Update ClamAV Database`
    - **User**: `root`
    - **Schedule**: Daily (recommended, e.g., 02:00 AM)

4. In the **Task Settings** tab, add the command:

```text
bash /volume1/scripts/clamav_updater/update_clamav.sh
```

5. Save and enable the task


## Files Downloaded

The script updates the following ClamAV database files:

- `main.cvd` - Main virus signatures
- `daily.cvd` - Daily updates
- `bytecode.cvd` - Bytecode signatures

## Logging

The script logs to both:

1. Console (stdout)
2. Log file: `/volume1/scripts/clamav_updater/update_clamav.log`

Logs include timestamps for all operations:

```text
[2024-01-15 14:30:00] === Starting ClamAV database update ===
[2024-01-15 14:30:00] Created directory: /volume1/scripts/clamav_updater/temp
[2024-01-15 14:30:00] Changing to temporary directory: /volume1/scripts/clamav_updater/temp
[2024-01-15 14:30:01] Downloading main.cvd (attempt 1/3)...
[2024-01-15 14:30:05] Successfully downloaded: main.cvd
[2024-01-15 14:30:10] Copying updates to: /var/packages/AntiVirus/target/engine/clamav/var/lib
[2024-01-15 14:30:11] Successfully copied: main.cvd
[2024-01-15 14:30:20] Cleaning temporary files...
[2024-01-15 14:30:20] === ClamAV database update completed successfully ===
```

## License

This script is provided as-is without warranty. Use at your own risk.

## References

- [ClamAV Official Documentation](https://docs.clamav.net/)
- [Microsoft ClamAV Repository](https://packages.microsoft.com/clamav)
- [Synology Antivirus Essential](https://www.synology.com/en-global/dsm/feature/antivirus_essential)
- [Synology Task Scheduler Guide](https://kb.synology.com/en-us/DSM/help/DSM/AdminCenter/system_taskscheduler?version=7)