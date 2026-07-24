#!/bin/bash
# Installer script for stat1090 traffic module (Landings & Departures tracking)

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "[+] Installing stat1090 traffic module to /usr/share/graphs1090/..."

# 1. Copy traffic.py
if [[ -d /usr/share/graphs1090 ]]; then
    cp "$SCRIPT_DIR/modules/traffic.py" /usr/share/graphs1090/traffic.py
    chmod +x /usr/share/graphs1090/traffic.py
    echo "  -> Copied traffic.py to /usr/share/graphs1090/traffic.py"
else
    echo "[!] Error: /usr/share/graphs1090 directory not found!"
    exit 1
fi

# 2. Add dump1090_ops type to dump1090.db if missing
DB_FILE="/usr/share/graphs1090/dump1090.db"
if [[ -f "$DB_FILE" ]]; then
    if ! grep -q "dump1090_ops" "$DB_FILE"; then
        echo "dump1090_ops		value:ABSOLUTE:0:U" >> "$DB_FILE"
        echo "  -> Added dump1090_ops type definition to $DB_FILE"
    fi
fi

# 3. Configure collectd to load traffic module
COLLECTD_CONF="/etc/collectd/collectd.conf"
CONF_D_DIR="/etc/collectd/collectd.conf.d"

if [[ -d "$CONF_D_DIR" ]]; then
    cp "$SCRIPT_DIR/modules/traffic.conf" "$CONF_D_DIR/traffic.conf"
    echo "  -> Installed config snippet to $CONF_D_DIR/traffic.conf"
elif [[ -f "$COLLECTD_CONF" ]]; then
    if ! grep -q 'Import "traffic"' "$COLLECTD_CONF"; then
        cat << 'EOF' >> "$COLLECTD_CONF"

# stat1090 Traffic Module (Landings & Departures)
<Plugin python>
    ModulePath "/usr/share/graphs1090"
    LogTraces true
    Import "traffic"
    <Module traffic>
        placeholder "true"
    </Module>
</Plugin>
EOF
        echo "  -> Added traffic module import to $COLLECTD_CONF"
    fi
fi

# 4. Restart collectd service to apply changes
echo "[+] Restarting collectd service..."
if systemctl is-active --quiet collectd; then
    systemctl restart collectd
    echo "[+] collectd service restarted successfully!"
else
    echo "[!] Warning: collectd service is not active. Please start collectd."
fi

echo "[+] Traffic module installation complete! RRD files dump1090_ops-landings.rrd and dump1090_ops-departures.rrd will be generated in memory."
