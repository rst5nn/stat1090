#!/bin/bash
set -e

IPATH="/usr/share/stat1090"
SPATH="$(cd "$(dirname "$0")" && pwd)"

echo "---------------------------------------------------"
echo " Installing stat1090 - ADS-B Performance Analytics"
echo "---------------------------------------------------"

# Check required dependencies
for cmd in rrdtool python3; do
    if ! command -v "$cmd" &>/dev/null; then
        echo "Missing required dependency: $cmd"
        if command -v apt-get &>/dev/null; then
            echo "Attempting to install $cmd via apt..."
            apt-get update && apt-get install -y "$cmd"
        else
            echo "Please install $cmd manually."
            exit 1
        fi
    fi
done

# Create destination directory
mkdir -p "$IPATH"
mkdir -p /var/lib/stat1090

# Copy project files
cp -r "$SPATH"/* "$IPATH/"

# Make scripts executable
chmod +x "$IPATH/stat1090.sh"
chmod +x "$IPATH/stat1090-server.py"
chmod +x "$IPATH/service-stat1090.sh"
chmod +x "$IPATH/cgi-bin/stat1090.cgi"

# Install systemd service
if [[ -d /etc/systemd/system ]]; then
    cp "$IPATH/stat1090.service" /etc/systemd/system/stat1090.service
    systemctl daemon-reload
    systemctl enable stat1090.service
    systemctl restart stat1090.service
    echo "stat1090 systemd service installed and started successfully!"
fi

# Lighttpd integration if present
if [[ -d /etc/lighttpd/conf-available ]]; then
    cp "$IPATH/88-stat1090.conf" /etc/lighttpd/conf-available/88-stat1090.conf
    if command -v lighty-enable-mod &>/dev/null; then
        lighty-enable-mod stat1090 proxy || true
        systemctl reload lighttpd &>/dev/null || true
    fi
fi

echo "---------------------------------------------------"
echo " stat1090 installation completed successfully!"
echo " Web Interface running at: http://localhost:8080"
echo "---------------------------------------------------"
