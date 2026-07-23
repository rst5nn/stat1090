# stat1090

**stat1090** is a streamlined, high-performance statistics and visualization web application for dump1090 / ADS-B receivers, inspired by `graphs1090`.

Unlike standard full-suite graph toolkits, `stat1090` focuses specifically on core receiver metrics with custom execution time window filtering (**`from`** and **`till`** values).

---

## Key Features

1. **Exact Time Range Filtering (`from` & `till`)**:
   - Interactively select exact **`from`** (Start Time) and **`till`** (End Time) date-time bounds via date-time pickers or API parameters.
   - Live URL synchronization (`?from=2026-07-22T08:00&till=2026-07-22T14:00`) for easy bookmarking and link sharing.
   - Quick preset timeframe buttons (`2h`, `8h`, `24h`, `48h`, `7d`, `14d`, `30d`, `90d`, `180d`, `365d`).

2. **Tailored Graph Set (3 Dedicated Core Graphs)**:
   - **ADS-B Range**: Maximum range (Nautical Miles/Statute Miles/km), average max range, median distance, and 1st-3rd quartile bounds.
   - **ADS-B Signal Level**: Peak signal level, median signal level, minimum signal (dBFS), and noise floor.
   - **ADS-B Aircraft Seen**: Total aircraft tracked categorized by positioning method (ADS-B position, MLAT, TIS-B, or without position).

3. **Modern Dynamic Architecture**:
   - Sleek glassmorphism web UI with dark mode, high-contrast typography, live refresh timer, loading spinners, and lightbox zoom.
   - Built-in lightweight Python web server and dynamic graph renderer (`stat1090-server.py`).
   - Standalone CGI script support (`cgi-bin/stat1090.cgi`) for Nginx and Lighttpd integration.

---

## Project Structure

```
stat1090/
├── html/
│   ├── index.html       # Web UI dashboard
│   ├── stat.css         # Glassmorphic dark styling
│   └── stat.js          # Time range & auto-refresh controller
├── cgi-bin/
│   └── stat1090.cgi     # CGI script for on-demand graph generation
├── stat1090.sh          # Core rrdtool graph rendering script
├── stat1090-server.py   # Standalone Python web server & API renderer
├── service-stat1090.sh  # Service launcher script
├── stat1090.service     # Systemd unit file
├── 88-stat1090.conf     # Lighttpd config snippet
├── nginx-stat1090.conf  # Nginx config snippet
├── install.sh           # Automated installation script
├── uninstall.sh         # Cleanup uninstaller
└── README.md            # Project documentation
```

---

## Installation

Run the automated installer:

```bash
sudo ./install.sh
```

Once installed, access the web dashboard at:
`http://<your-pi-ip>:8080/`

---

## API Usage for Dynamic Graphs

You can query graphs directly by passing `type`, `from`, and `till` parameters:

```
GET /api/graph?type={range|signal|aircraft}&from={start}&till={end}
```

### Examples:

- **Custom Datetime Range**:
  ```
  http://localhost:8080/api/graph?type=range&from=2026-07-22T08:00&till=2026-07-22T14:00
  ```

- **Unix Timestamp Range**:
  ```
  http://localhost:8080/api/graph?type=signal&from=1784716800&till=1784738400
  ```

- **Relative Preset Range**:
  ```
  http://localhost:8080/api/graph?type=aircraft&from=48h&till=now
  ```

---

## License

MIT License.
