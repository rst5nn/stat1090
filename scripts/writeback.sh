#!/bin/bash
# stat1090 writeback: persist RRD from RAM to disk
SOURCE="/run/collectd"
ARCHIVE_DIR="/var/lib/collectd/rrd"
ARCHIVE="$ARCHIVE_DIR/localhost.tar.gz"

mkdir -p "$ARCHIVE_DIR"
[[ -d "$SOURCE/localhost" ]] || exit 0

TMP="$ARCHIVE_DIR/.tmp_$$.tar.gz"
tar czf "$TMP" -C "$SOURCE" localhost && gzip -t "$TMP" &>/dev/null && {
    mv "$TMP" "$ARCHIVE"
    # Weekly auto-backup
    WEEKLY="$ARCHIVE_DIR/auto-backup-$(date +%Y-week_%V).tar.gz"
    [[ -f "$WEEKLY" ]] || cp "$ARCHIVE" "$WEEKLY"
    find "$ARCHIVE_DIR" -name 'auto-backup-*.tar.gz' -mtime +60 -delete
    echo "stat1090: archived to $ARCHIVE"
} || rm -f "$TMP"
