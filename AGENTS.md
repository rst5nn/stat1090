# AGENTS.md — stat1090

## What is stat1090

stat1090 is a lightweight ADS-B receiver statistics dashboard for dump1090.
It renders RRDtool graphs on demand via a multithreaded Python HTTP server and displays them
in a glassmorphism-styled single-page web UI with exact time range filtering.

It is designed for Raspberry Pi / SBC deployments running dump1090 + collectd,
and is inspired by (and coexists with) [graphs1090](https://github.com/wiedehopf/graphs1090).

## Architecture

```
Browser (index.html + stat.js + stat.css)
  │
  │  GET /api/graph?type=range&from=24h&till=now&theme=dark
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
collectd RRD databases (/run/collectd/localhost/dump1090-*/  or  /var/lib/collectd/rrd/localhost/dump1090-*/)
```

### Data flow

1. collectd polls dump1090's stats JSON every 60s and writes to `.rrd` files.
2. `.rrd` files live in `/run/collectd` (tmpfs) at runtime; they are flushed to
   `/var/lib/collectd/rrd` on disk via `systemctl restart collectd` (or `backup-collectd.sh`).
3. `stat1090.sh` reads the `.rrd` files with `rrdtool graph` and outputs a PNG.
4. `stat1090-server.py` wraps this in a multithreaded HTTP API (`ThreadingMixIn`), creating a temp file per request.
5. The browser JS polls the API on a configurable refresh interval (Off, 60s, 300s).

### Component responsibilities

| File | Role |
|------|------|
| `stat1090-server.py` | Multithreaded Python HTTP server (`ThreadingHTTPServer`). Serves static files from `html/` and handles `/api/graph` + `/api/status`. Validates inputs, spawns `stat1090.sh` via subprocess. |
| `stat1090.sh` | Core RRDtool graph renderer. Accepts `type`, output path, `from`, `till`, hostname, db dir, and colorscheme args. Supports 5 graph types (`range`, `signal`, `aircraft`, `messages`, `tracks`). Uses bash arrays for safe argument passing. |
| `html/index.html` | Semantic HTML5 dashboard with inline SVGs. Displays active graph cards (`range`, `signal`, `aircraft`). |
| `html/stat.css` | CSS with custom properties for dark/light theming (`#121214` dark / `#f8fafc` bright). Glassmorphism cards, responsive grid, modal lightbox. |
| `html/stat.js` | Frontend controller. Manages preset/custom time ranges, auto-refresh, 24-hour military time, URL deep-linking, theme toggle, image preloading, PNG saving. |
| `cgi-bin/stat1090.cgi` | Legacy CGI alternative to the Python server. Parses `QUERY_STRING`, calls `stat1090.sh`, returns PNG. Only used if the Python server is not deployed. |
| `service-stat1090.sh` | Systemd service wrapper. Sets `renice 20`, exports `PORT`/`HOST`, execs the Python server. |
| `stat1090.service` | Systemd unit. Runs as `stat1090` user (not root). `Nice=19`, `CPUSchedulingPolicy=idle`. |
| `88-stat1090.conf` | Lighttpd config snippet. Aliases `/stat1090/` → `html/`, proxies `/stat1090/api/` → `:8080`. |
| `nginx-stat1090.conf` | Nginx config snippet. Same aliasing and proxying as the Lighttpd config. |
| `install.sh` | Installer. Creates `stat1090` system user, copies files to `/usr/share/stat1090`, installs systemd service, configures Lighttpd if present. |
| `uninstall.sh` | Cleanup. Stops service, removes configs, schedules directory removal via temp script. |
| `backup-collectd.sh` | Backup script. Archives `/var/lib/collectd`, uploads to Google Drive via rclone, rotates to keep 7 newest (flushing to disk configured via `/etc/cron.d/collectd_to_disk`). |

## Graph Types & Visual Styling

All graphs follow the `@antigravity-design-expert` color palette and unified area fill system:

- **Unified Area Fill (`AREA_FILL_PRIMARY`)**: Deep Emerald (`#1c3d2e`) in Dark mode, Soft Mint (`#E6F4EA`) in Light mode.

| Type | RRD files used | Key metrics & Visual Features |
|------|---------------|-------------------------------|
| `range` | `dump1090_range-max_range.rrd`, `dump1090_range-minimum.rrd`, `dump1090_range-median.rrd` | Max range (`#38bdf8`), peak distance line (`#818cf8`), average max range (`#888888`), median distance (`#fbbf24`), closest distance (`#f43f5e`). |
| `signal` | `dump1090_dbfs-signal.rrd`, `dump1090_dbfs-min_signal.rrd`, `dump1090_dbfs-median.rrd`, `dump1090_dbfs-peak_signal.rrd`, `dump1090_dbfs-noise.rrd` | Peak signal (`#f43f5e`), median signal (`#38bdf8`), min signal (`#fbbf24`), noise floor line (`#34d399`), noise area fill (from `-45 dBFS` to noise line), `-3 dBFS` dashed reference line (`#888888`). |
| `aircraft` | `dump1090_aircraft-recent.rrd`, `dump1090_gps-recent.rrd` | Total tracked area fill (`AREA_FILL_PRIMARY`) with crisp mint green boundary line (`#34d399`), ADS-B position count (`#38bdf8`). |
| `messages` | `dump1090_messages-local_accepted.rrd`, `dump1090_messages-remote_accepted.rrd`, `dump1090_messages-strong_signals.rrd` | msgs/sec, strong signal percentage. |
| `tracks` | `dump1090_tracks-all.rrd`, `dump1090_tracks-single_message.rrd` | Tracks/hour, 8-min EMA smoothing. |

## RRD Database Locations

The script auto-discovers the database directory:
- **Primary**: `/run/collectd/localhost/dump1090-localhost/` (tmpfs, fast)
- **Fallback**: `/var/lib/collectd/rrd/localhost/dump1090-localhost/` (disk)
- Wildcard fallback via `find` if the hostname-based path doesn't exist.

## Color Scheme & Design System

Two themes supported, selected via `?theme=dark` or `?theme=light` query param:
- **Dark** (default): `#121214` canvas, glassmorphism card surfaces, emerald/cyan/rose accents.
- **Light**: `#f8fafc` canvas, white glass cards, high-contrast accent variants.

Colors are defined as bash variables in `stat1090.sh` and passed to `rrdtool graph`
via the `COLORS` bash array. The CSS theme uses `data-theme` attribute on `<html>`.

## API

### `GET /api/graph`

| Param | Required | Default | Description |
|-------|----------|---------|-------------|
| `type` | yes | `aircraft` | Graph type: `range`, `signal`, `aircraft`, `messages`, `tracks` (plus aliases) |
| `from` | no | `24h` | Start time: relative (`24h`, `7d`), ISO datetime (`2026-07-22T08:00`), or Unix epoch |
| `till` | no | `now` | End time: same formats as `from` |
| `host` | no | `localhost` | collectd hostname |
| `theme` | no | `dark` | Color scheme: `dark` or `light` |

Returns: `image/png`, `Cache-Control: no-cache`

### `GET /api/status`

Returns JSON with server status, available graph types, DB path, rrdtool presence.

## Installation Target Layout

```
/usr/share/stat1090/          # All project files
/var/lib/stat1090/            # Working directory (empty.rrd, temp files)
/etc/systemd/system/stat1090.service
/etc/lighttpd/conf-available/88-stat1090.conf  (if lighttpd present)
```

## Configuration

Optional `/etc/default/stat1090` file can override:
- `GRAPH_WIDTH` (default: 1100)
- `GRAPH_HEIGHT` (default: 340)
- `GRAPH_COLOR_SCHEME` (default: dark)
- `RANGE_UNIT` (default: nautical; options: statute, metric)

Environment variables for the server (via systemd or shell):
- `PORT` (default: 8080)
- `HOST` (default: 0.0.0.0)

## Development Notes

- The Python server uses `ThreadingMixIn + HTTPServer` so concurrent graph requests from the dashboard execute in parallel threads without queuing.
- `stat1090.sh` uses a `check_rrd()` helper that falls back to an empty RRD file when a data source doesn't exist, preventing rrdtool from erroring out.
- All shell variables for rrdtool arguments use **bash arrays** (`"${COLORS[@]}"`, `"${START_OPT[@]}"`) to avoid word-splitting bugs.
- `88-stat1090.conf` scopes lighttpd aliasing strictly to `/stat1090/` so other services like `tar1090` and `graphs1090` function without routing interference.
- The service runs as a dedicated `stat1090` system user, not root.
- All timestamps use 24-hour military time (`HH:mm` / `HH:mm:ss`) and date inputs use `lang="en-GB"`.
- URL query params are synced bidirectionally: preset/custom selections update the URL, and loading a URL with `?from=...&till=...` restores the custom range.

## Dependencies

- `rrdtool` — graph rendering
- `python3` — HTTP server (stdlib only, no pip packages)
- `collectd` — data collection (with dump1090 plugin from graphs1090)
- `lighttpd` or `nginx` — reverse proxy (optional, can run standalone on :8080)
- `rclone` — Google Drive backup (only for `backup-collectd.sh`)
