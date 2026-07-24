#!/bin/bash
# stat1090 readback: restore RRD archive from disk to RAM
ARCHIVE="/var/lib/collectd/rrd/localhost.tar.gz"
TARGET="/run/collectd"

mkdir -p "$TARGET"

for archive in "$ARCHIVE" /var/lib/collectd/rrd/auto-backup-*.tar.gz; do
    if [[ -f "$archive" ]] && gzip -t "$archive" &>/dev/null; then
        tar xzf "$archive" -C "$TARGET" 2>/dev/null && {
            find "$TARGET" -name '*.rrd' -size 0 -delete
            echo "stat1090: restored from $archive"
            exit 0
        }
    fi
done
echo "stat1090: no valid archive, starting fresh."
