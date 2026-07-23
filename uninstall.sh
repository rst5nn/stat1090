#!/bin/bash
set -e

echo "Uninstalling stat1090..."

if systemctl is-active --quiet stat1090.service &>/dev/null; then
    systemctl stop stat1090.service || true
fi

if systemctl is-enabled --quiet stat1090.service &>/dev/null; then
    systemctl disable stat1090.service || true
fi

rm -f /etc/systemd/system/stat1090.service
systemctl daemon-reload &>/dev/null || true

rm -rf /usr/share/stat1090
rm -rf /var/lib/stat1090

if [[ -f /etc/lighttpd/conf-available/88-stat1090.conf ]]; then
    rm -f /etc/lighttpd/conf-available/88-stat1090.conf
    systemctl reload lighttpd &>/dev/null || true
fi

echo "stat1090 uninstalled successfully."
