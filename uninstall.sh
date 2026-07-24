#!/bin/bash
set -e

echo "=== Uninstalling stat1090 ==="

# 1. Stop services
systemctl stop stat1090 2>/dev/null || true
systemctl disable stat1090 2>/dev/null || true

# 2. Remove systemd service and cron
rm -f /etc/systemd/system/stat1090.service
rm -f /etc/cron.d/stat1090

# 3. Restore pre-stat1090 collectd config if available
if [[ -f /etc/collectd/collectd.conf.pre-stat1090 ]]; then
    mv /etc/collectd/collectd.conf.pre-stat1090 /etc/collectd/collectd.conf
    echo "Restored pre-stat1090 collectd.conf"
fi

# 4. Remove malarky drop-in
rm -f /etc/systemd/system/collectd.service.d/malarky.conf
rmdir /etc/systemd/system/collectd.service.d 2>/dev/null || true

# 5. Lighttpd cleanup
rm -f /etc/lighttpd/conf-available/88-stat1090.conf
rm -f /etc/lighttpd/conf-enabled/88-stat1090.conf
systemctl restart lighttpd 2>/dev/null || true

# 6. Remove stat1090 binaries
rm -rf /usr/share/stat1090

systemctl daemon-reload
systemctl restart collectd 2>/dev/null || true

echo "---------------------------------------------------"
echo " stat1090 uninstalled."
echo " Preserved: /var/lib/stat1090/ (data/empty.rrd)"
echo " Preserved: /etc/default/stat1090.cfg (config)"
echo " Preserved: /var/lib/collectd/rrd/ (RRD database)"
echo "---------------------------------------------------"
