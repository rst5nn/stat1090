#!/usr/bin/env python3
"""
stat1090 Web Server & Dynamic Graph Renderer
Serves web interface and dynamically generates graphs for 'range', 'signal', and 'aircraft'
with custom 'from' and 'till' time ranges.
"""

import os
import sys
import re
import time
import tempfile
import subprocess
import urllib.parse
from http.server import HTTPServer, SimpleHTTPRequestHandler
from socketserver import ThreadingMixIn
from datetime import datetime

class ThreadingHTTPServer(ThreadingMixIn, HTTPServer):
    """Multithreaded HTTP server handling concurrent graph requests cleanly."""
    daemon_threads = True

PORT = int(os.environ.get("PORT", "8080"))
HOST = os.environ.get("HOST", "0.0.0.0")
BASE_DIR = os.path.dirname(os.path.realpath(__file__))
HTML_DIR = os.path.join(BASE_DIR, "html")

def find_stat_sh():
    candidates = [
        os.path.join(BASE_DIR, "stat1090.sh"),
        "/usr/share/stat1090/stat1090.sh",
        "/home/yk/proj/stat1090/stat1090.sh"
    ]
    for candidate in candidates:
        if os.path.exists(candidate):
            return candidate
    return candidates[0]

STAT_SH = find_stat_sh()
ALLOWED_GRAPHS = {"range", "signal", "aircraft", "messages", "tracks", "adsb_range", "signal_level", "aircraft_seen", "message_rate", "messages_received", "tracks_seen", "adsb_tracks_seen"}

def sanitize_time_param(val):
    """Sanitize time inputs to prevent shell injection while allowing timestamps, dates, and relative formats."""
    if not val:
        return ""
    val = val.strip()
    # Allow epoch numbers, relative times like 24h, 7d, ISO strings like 2026-07-22T10:00:00Z
    if re.match(r'^[a-zA-Z0-9\:\-\+\._]{1,64}$', val):
        return val
    return ""

class Stat1090RequestHandler(SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=HTML_DIR, **kwargs)

    def do_HEAD(self):
        return self.do_GET()

    def do_GET(self):
        parsed = urllib.parse.urlparse(self.path)
        path = parsed.path
        query = urllib.parse.parse_qs(parsed.query)

        # Dynamic graph generation endpoint
        if path.endswith("/api/graph") or path.endswith("/graph") or path in ("/api/graph", "/graph", "/graphs"):
            return self.handle_graph_request(query)
        
        # API status endpoint
        if path.endswith("/api/status") or path in ("/api/status", "/status"):
            return self.handle_status_request()

        # Fallback to serving static HTML assets
        return super().do_GET()

    def handle_graph_request(self, query):
        graph_type = query.get("type", query.get("graph", ["aircraft"]))[0]
        from_val = query.get("from", ["24h"])[0]
        till_val = query.get("till", ["now"])[0]
        host_val = query.get("host", ["localhost"])[0]

        # Standardize graph type
        if graph_type == "adsb_range":
            graph_type = "range"
        elif graph_type in ("signal_level", "dbfs"):
            graph_type = "signal"
        elif graph_type in ("aircraft_seen", "aircrafts"):
            graph_type = "aircraft"
        elif graph_type in ("message_rate", "messages_received", "msgs"):
            graph_type = "messages"
        elif graph_type in ("tracks_seen", "adsb_tracks_seen"):
            graph_type = "tracks"

        if graph_type not in ALLOWED_GRAPHS:
            self.send_error(400, f"Invalid graph type. Allowed: {', '.join(ALLOWED_GRAPHS)}")
            return

        clean_from = sanitize_time_param(from_val) or "24h"
        clean_till = sanitize_time_param(till_val) or "now"
        clean_host = sanitize_time_param(host_val) or "localhost"

        # Convert ISO datetime (e.g. 2026-07-22T14:30) to epoch timestamp if passed from datetime-local input
        clean_from = self.convert_iso_to_epoch(clean_from)
        clean_till = self.convert_iso_to_epoch(clean_till)
        theme_val = query.get("theme", query.get("colorscheme", ["dark"]))[0].lower()
        if theme_val in ("light", "bright"):
            theme_val = "light"
        else:
            theme_val = "dark"

        # Generate PNG in temporary file
        with tempfile.NamedTemporaryFile(suffix=".png", delete=False) as tmp_file:
            tmp_path = tmp_file.name

        try:
            stat_script = find_stat_sh()
            cmd = ["bash", stat_script, graph_type, tmp_path, clean_from, clean_till, clean_host, "", theme_val]
            result = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=15)

            if result.returncode == 0 and os.path.exists(tmp_path) and os.path.getsize(tmp_path) > 0:
                with open(tmp_path, "rb") as f:
                    png_data = f.read()

                self.send_response(200)
                self.send_header("Content-Type", "image/png")
                self.send_header("Content-Length", str(len(png_data)))
                self.send_header("Cache-Control", "no-cache, no-store, must-revalidate")
                self.send_header("Pragma", "no-cache")
                self.send_header("Expires", "0")
                self.end_headers()
                self.wfile.write(png_data)
            else:
                err_msg = result.stderr or f"Graph script exited with code {result.returncode}."
                print(f"[ERROR] Graph generation failed for {graph_type}: {err_msg}", file=sys.stderr)
                self.send_error(500, f"Graph generation error: {err_msg}")
        except Exception as e:
            print(f"[ERROR] Exception generating graph {graph_type}: {str(e)}", file=sys.stderr)
            self.send_error(500, f"Server error generating graph: {str(e)}")
        finally:
            if os.path.exists(tmp_path):
                try:
                    os.remove(tmp_path)
                except OSError:
                    pass

    def convert_iso_to_epoch(self, val):
        if not val or val == "now":
            return val
        if "T" in val or "-" in val:
            val_clean = val.replace("T", " ")
            for fmt in ("%Y-%m-%d %H:%M:%S", "%Y-%m-%d %H:%M", "%Y-%m-%d"):
                try:
                    dt = datetime.strptime(val_clean, fmt)
                    return str(int(dt.timestamp()))
                except ValueError:
                    pass
        return val

    def handle_status_request(self):
        import json
        db_dir = "/var/lib/collectd/rrd"
        if os.path.exists("/run/collectd/localhost"):
            db_dir = "/run/collectd"
            
        status = {
            "name": "stat1090",
            "status": "online",
            "time": datetime.now().isoformat(),
            "epoch": int(time.time()),
            "graphs": ["range", "signal", "aircraft", "messages", "tracks"],
            "db_path": db_dir,
            "rrdtool_installed": os.path.exists("/usr/bin/rrdtool") or os.path.exists("/usr/local/bin/rrdtool")
        }
        body = json.dumps(status, indent=2).encode('utf-8')
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

def main():
    print(f"Starting stat1090 server on {HOST}:{PORT}")
    print(f"Serving web interface from: {HTML_DIR}")
    print(f"Graph renderer script: {STAT_SH}")
    
    server = ThreadingHTTPServer((HOST, PORT), Stat1090RequestHandler)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nShutting down stat1090 server.")
        server.server_close()

if __name__ == "__main__":
    main()
