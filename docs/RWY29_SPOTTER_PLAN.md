# EPGD Airport Traffic Plan (Altitude & Speed Filtered)

## 1. Overview & Goal

- **Airport**: Gdańsk Lech Wałęsa Airport (GDN / EPGD)
- **Challenge**: Frequent **GNSS / GPS Jamming in the Baltic region** causes aircraft to transmit Mode-S data without GPS coordinates (`lat`/`lon` missing).
- **Strategy**: 100% Coordinate-Free Filter using only **Altitude**, **Ground/Indicated Speed**, and **Vertical Rate**.
- **Storage Strategy**: Dual RAM/Disk RRD database (`tmpfs` in RAM at `/run/collectd/localhost/stat1090-localhost/stat1090_ops-*.rrd`), zero SQL database overhead.

---

## 2. Coordinate-Free Filter Criteria

The `stat1090.py` collectd plugin in `/usr/share/stat1090/stat1090.py` evaluates `/run/readsb/aircraft.json` every 60 seconds:

- **Altitude Window**: `alt <= 4,500 ft AMSL` (configurable via `/etc/default/stat1090.conf`).
- **Speed Window**: `125 kts <= speed <= 250 kts` (configurable; filters out light GA circuits and slow helicopters).
- 🛬 **Landings (Arrivals)**: `baro_rate < -200 fpm` (descending).
- 🛫 **Departures**: `baro_rate > +200 fpm` (climbing).
- **De-duplication**: 15-minute (`900s`) cooldown per aircraft ICAO hex code.
- **Category Filter**: `A2, A3, A4, A5` (configurable).
- **Commercial Prefix Filter**: Optional 3-letter ICAO callsign prefix matching (configurable).

---

## 3. RRD Storage & Graph Rendering

- **RAM RRD Path**: `/run/collectd/localhost/stat1090-localhost/stat1090_ops-landings.rrd` & `stat1090_ops-departures.rrd`
- **Graph Math ([`stat1090.sh`](file:///home/yk/proj/stat1090/stat1090.sh))**:
  - Cumulative hourly sawtooth counter: `CDEF:landings=TIME,3600,%,0,EQ,0,PREV,UN,0,PREV,IF,IF,landings_int,+`
  - Resets to 0 at the top of every hour, increments with each detected event.
