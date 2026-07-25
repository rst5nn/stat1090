# AGENTS.md — stat1090

## What is stat1090

`stat1090` is a standalone, lightweight, high-performance ADS-B receiver statistics dashboard and spotter for dump1090 / readsb.
It renders RRDtool graphs on demand via a multithreaded Python HTTP server and displays them in a glassmorphism-styled single-page web UI with exact time range filtering (`from` and `till`).

It is designed for Raspberry Pi and single-board computer (SBC) deployments running dump1090 / readsb with collectd.

## Architecture

```
Browser (index.html + stat.js + stat.css)
  │
  │  GET /api/graph?type=traffic&from=24h&till=now&theme=dark
  ▼
Lighttpd or Nginx (reverse proxy on /stat1090/api/)
  │
  │  proxy_pass :8080
  ▼
stat1090-server.py (ThreadingHTTPServer / ThreadingMixIn on port 8080)
  │
  │  subprocess.run(["bash", "stat1090.sh", type, tmpfile, from, till, host, "", theme])
  ▼
stat1090.sh (bash + rrdtool graph → PNG)
  │
  │  reads .rrd files
  ▼
collectd RRD databases (/run/collectd/localhost/dump1090-*/  and  /run/collectd/localhost/stat1090-*/)
```

### Data Flow & Unified Collector

1. **`stat1090.py`**: A single, unified Python collectd plugin (`/usr/share/stat1090/stat1090.py`) executes 3 data collection loops every 60s:
   - `read_1090()`: Polls `stats.json` and `aircraft.json` for message rates, aircraft counts, signal levels, ranges, tracks, and CPU metrics.
   - `read_traffic()`: Evaluates landing & departure approach thresholds against `/etc/default/stat1090.conf` (altitude, speed, categories, callsigns).
   - `read_temperature()`: Polls sysfs thermal zones (`/sys/class/thermal/thermal_zone*/temp`) and dispatches °C values.
2. **RAM Storage (`tmpfs`)**: `.rrd` files live in `/run/collectd` (tmpfs) at runtime; they are flushed to `/var/lib/collectd/rrd` on disk on collectd stop (`writeback.sh`) or daily via `/etc/cron.d/stat1090`.
3. **On-Demand Rendering**: `stat1090.sh` reads the `.rrd` files with `rrdtool graph` and outputs a PNG.
4. **API Wrapper**: `stat1090-server.py` wraps this in a multithreaded HTTP API (`ThreadingMixIn`), serving static UI assets and dynamic PNG graphs.

### Component Responsibilities

| File | Role |
|------|------|
| `stat1090.py` | Unified Python collectd plugin. Combines core ADS-B statistics, GNSS-resilient traffic spotter, and thermal zone collectors. |
| `stat1090.db` | Custom TypesDB file containing type definitions for dump1090 metrics, `dump1090_ops` (traffic), and `temperature`. |
| `stat1090.conf` | Configuration file deployed to `/etc/default/stat1090.conf`. Controls spotter speed limits, max altitude, commercial prefixes, and allowed categories. |
| `collectd-stat1090.conf` | Standalone collectd config template. Deployed to `/etc/collectd/collectd.conf`. |
| `stat1090-server.py` | Multithreaded Python HTTP server (`ThreadingHTTPServer`). Serves static files from `html/` and handles `/api/graph` + `/api/status`. |
| `stat1090.sh` | Core RRDtool graph renderer. Supports 5 graph types (`range`, `signal`, `aircraft`, `traffic`, `temperature`). |
| `scripts/readback.sh` | RAM restore script. Unpacks `/var/lib/collectd/rrd/localhost.tar.gz` to `/run/collectd` on collectd start. |
| `scripts/writeback.sh` | RAM archive script. Packs `/run/collectd/localhost` to `/var/lib/collectd/rrd/localhost.tar.gz` on collectd stop and keeps 60-day weekly backups. |
| `scripts/malarky.conf` | Systemd drop-in template for `collectd.service` executing `readback.sh` on start and `writeback.sh` on stop. |
| `html/index.html` | Semantic HTML5 dashboard with inline SVGs for 5 graph cards (`range`, `signal`, `aircraft`, `traffic`, `temperature`). |
| `html/stat.css` | Glassmorphism CSS with custom properties for dark/light theming (`#121214` dark / `#f8fafc` bright). |
| `html/stat.js` | Frontend controller. Manages preset/custom time ranges, auto-refresh, 24-hour military time, URL deep-linking, theme toggle, and lightbox zoom. |
| `install.sh` | Standalone installer. Deploys project files, replaces collectd config, installs systemd service and cron tasks. |
| `uninstall.sh` | Cleanup uninstaller. Removes stat1090 files and restores previous collectd config. |
| `backup-collectd.sh` | Backup script. Archives `/var/lib/collectd`, uploads to Google Drive via rclone, and rotates backups. |

---

## Graph Types & Visual Styling

All graphs follow a high-contrast dark/bright design system with mirrored Y-axes where appropriate:

| Type | RRD files used | Key metrics & Visual Features |
|------|---------------|-------------------------------|
| `range` | `dump1090_range-max_range.rrd`, `dump1090_range-minimum.rrd`, `dump1090_range-median.rrd` | Max range (`#38bdf8`), peak distance line (`#818cf8`), average max range (`#888888`), median distance (`#fbbf24`), closest distance (`#f43f5e`). |
| `signal` | `dump1090_dbfs-signal.rrd`, `dump1090_dbfs-min_signal.rrd`, `dump1090_dbfs-median.rrd`, `dump1090_dbfs-peak_signal.rrd`, `dump1090_dbfs-noise.rrd` | Peak signal (`#f43f5e`), median signal (`#38bdf8`), min signal (`#fbbf24`), noise floor line (`#34d399`), noise area fill, `-3 dBFS` reference line. |
| `aircraft` | `dump1090_aircraft-recent.rrd`, `dump1090_gps-recent.rrd` | Total tracked area fill (`#1c3d2e`/`#E6F4EA`) with crisp mint green boundary (`#34d399`), ADS-B position count (`#38bdf8`). |
| `traffic` | `dump1090_ops-landings.rrd`, `dump1090_ops-departures.rrd` | Cumulative hourly flight counter (sawtooth area chart resetting on the hour). Landings (`#34d399`), Departures (`#38bdf8`), Max/Hour peak stats. |
| `temperature` | `stat1090-localhost/temperature-*.rrd` (or `table-localhost/gauge-cpu_temp.rrd`) | System CPU/GPU thermal zone temperatures in °C. Symmetrical left and right Y-axes (`°C`), Avg/Max/Min GPRINT stats. |

---

## Installation Target Layout

```
/usr/share/stat1090/              # Flat application root (stat1090.py, stat1090.db, stat1090.sh, server, html)
/usr/share/stat1090/scripts/      # RAM persistence scripts (readback.sh, writeback.sh, malarky.conf)
/usr/share/stat1090/data-symlink/ # Symlink to decoder (/run/readsb)
/etc/default/stat1090.conf        # Spotter configuration
/etc/collectd/collectd.conf       # Standalone collectd config
/etc/cron.d/stat1090              # Daily flush & backup cron
/etc/systemd/system/stat1090.service
```

---

## API Usage

### `GET /api/graph`

| Param | Required | Default | Description |
|-------|----------|---------|-------------|
| `type` | yes | `aircraft` | Graph type: `range`, `signal`, `aircraft`, `traffic`, `temperature` |
| `from` | no | `24h` | Start time: relative (`24h`, `7d`), ISO datetime (`2026-07-22T08:00`), or Unix epoch |
| `till` | no | `now` | End time: same formats as `from` |
| `host` | no | `localhost` | collectd hostname |
| `theme` | no | `dark` | Color scheme: `dark` or `light` |

Returns: `image/png`, `Cache-Control: no-cache`

### `GET /api/status`

Returns JSON with server status, available graph types, active DB path, and rrdtool presence.
