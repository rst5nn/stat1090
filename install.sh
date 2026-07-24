#!/bin/bash
set -e

IPATH="/usr/share/stat1090"
REPO="$(cd "$(dirname "$0")" && pwd)"

echo "---------------------------------------------------"
echo " Installing stat1090 - Standalone ADS-B Analytics"
echo "---------------------------------------------------"

# 1. Dependencies
for pkg in rrdtool collectd-core python3; do
    if ! dpkg -s "$pkg" &>/dev/null; then
        echo "Installing $pkg..."
        apt-get install -y "$pkg"
    fi
done

# 2. Stop graphs1090 service if present
systemctl stop graphs1090 2>/dev/null || true
systemctl disable graphs1090 2>/dev/null || true

# 3. Create destination directories
mkdir -p "$IPATH"/{modules,scripts,html}
mkdir -p /var/lib/collectd/rrd
mkdir -p /var/lib/stat1090

# 4. Deploy stat1090 files
cp "$REPO"/stat1090.sh "$IPATH/"
cp "$REPO"/stat1090-server.py "$IPATH/"
cp "$REPO"/service-stat1090.sh "$IPATH/"
cp "$REPO"/backup-collectd.sh "$IPATH/"
cp "$REPO"/dump1090.db "$IPATH/"
cp -r "$REPO"/html/* "$IPATH/html/"
cp "$REPO"/modules/*.py "$IPATH/modules/"
cp "$REPO"/scripts/*.sh "$IPATH/scripts/"
cp "$REPO"/scripts/malarky.conf "$IPATH/scripts/"
chmod +x "$IPATH"/scripts/*.sh "$IPATH"/*.sh

# 5. Config files (preserve user config, backup pre-stat1090 collectd.conf)
if [[ ! -f /etc/default/stat1090.cfg ]]; then
    cp "$REPO"/stat1090.cfg /etc/default/stat1090.cfg
fi
if [[ -f /etc/collectd/collectd.conf ]] && [[ ! -f /etc/collectd/collectd.conf.pre-stat1090 ]]; then
    cp /etc/collectd/collectd.conf /etc/collectd/collectd.conf.pre-stat1090
fi
cp "$REPO"/collectd-stat1090.conf /etc/collectd/collectd.conf

# 6. Data symlink to active decoder
mkdir -p "$IPATH/data-symlink"
for candidate in /run/readsb /run/dump1090-fa /run/dump1090; do
    if [[ -d "$candidate" ]]; then
        ln -snf "$candidate" "$IPATH/data-symlink/data"
        break
    fi
done

# 7. Malarky drop-in (RAM persistence)
mkdir -p /etc/systemd/system/collectd.service.d
cp "$IPATH/scripts/malarky.conf" /etc/systemd/system/collectd.service.d/malarky.conf

# 8. Empty RRD fallback
EMPTY="/var/lib/stat1090/empty.rrd"
if [[ ! -f "$EMPTY" ]]; then
    rrdtool create "$EMPTY" --step 60 \
        DS:value:GAUGE:120:U:U RRA:AVERAGE:0.5:1:1
fi

# 9. Systemd services
cp "$REPO"/stat1090.service /etc/systemd/system/stat1090.service
systemctl daemon-reload
systemctl enable stat1090.service

# 10. Daily cron tasks (flush & backup)
cat > /etc/cron.d/stat1090 <<'EOF'
# stat1090: restart collectd daily to flush RAM to disk
42 23 * * * root /bin/systemctl restart collectd
# stat1090: daily RRD backup
0 1 * * * root /usr/share/stat1090/backup-collectd.sh >> /var/log/stat1090-backup.log 2>&1
EOF

# 11. Lighttpd integration if present
if [[ -d /etc/lighttpd/conf-available ]]; then
    cp "$REPO"/88-stat1090.conf /etc/lighttpd/conf-available/88-stat1090.conf
    if command -v lighty-enable-mod &>/dev/null; then
        lighty-enable-mod stat1090 proxy || true
        systemctl reload lighttpd &>/dev/null || true
    fi
fi

# 12. Restart collectd and stat1090
systemctl restart collectd
systemctl restart stat1090

echo "---------------------------------------------------"
echo " stat1090 installation completed successfully!"
echo " Web Interface running at: http://localhost:8080"
echo "---------------------------------------------------"
