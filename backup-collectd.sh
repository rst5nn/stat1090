#!/bin/bash
# Backup script for collectd statistics to Google Drive via rclone
# Flushes collectd memory data to disk before archiving and keeps the 7 newest backups.

set -e

if ! command -v rclone &> /dev/null; then
    echo "[ERROR] rclone is not installed. Please install rclone to use this backup script."
    exit 1
fi

DATE=$(date +%Y-%m-%d_%H%M)
ARCHIVE="/tmp/collectd_${DATE}.tar.gz"
REMOTE="gdrive:ADSB"

trap 'rm -f "$ARCHIVE"' EXIT

# Locate rclone config file
RCLONE_CONF_OPT=""
if [[ -f "${HOME}/.config/rclone/rclone.conf" ]]; then
    RCLONE_CONF_OPT="--config ${HOME}/.config/rclone/rclone.conf"
elif [[ -f "/etc/rclone.conf" ]]; then
    RCLONE_CONF_OPT="--config /etc/rclone.conf"
fi

echo "[$(date +'%Y-%m-%d %H:%M:%S')] Starting collectd backup..."

# 1. Archive collectd directory
echo "[+] Creating archive $ARCHIVE..."
if [[ -d /var/lib/collectd ]]; then
    tar -czf "$ARCHIVE" -C /var/lib collectd
else
    echo "[!] /var/lib/collectd not found, falling back to /run/collectd..."
    tar -czf "$ARCHIVE" -C /run collectd
fi

# 3. Copy archive to Google Drive using rclone
echo "[+] Uploading $ARCHIVE to $REMOTE..."
rclone $RCLONE_CONF_OPT copy "$ARCHIVE" "$REMOTE" --quiet

# 4. Rotate Google Drive backups (keep only the 7 newest backups)
echo "[+] Rotating Google Drive backups (keeping 7 newest)..."
OLD_BACKUPS=$(rclone $RCLONE_CONF_OPT lsf "$REMOTE" --files-only --include "collectd_*.tar.gz" 2>/dev/null | sort -r | tail -n +8)

if [[ -n "$OLD_BACKUPS" ]]; then
    while IFS= read -r file; do
        if [[ -n "$file" ]]; then
            echo "[ - ] Removing old Google Drive backup: $file"
            rclone $RCLONE_CONF_OPT deletefile "$REMOTE/$file" --quiet
        fi
    done <<< "$OLD_BACKUPS"
else
    echo "[+] No old backups to purge (7 or fewer backups present)."
fi

echo "[$(date +'%Y-%m-%d %H:%M:%S')] Collectd backup completed successfully!"
