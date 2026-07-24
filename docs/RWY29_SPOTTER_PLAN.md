# EPGD Airport Traffic Plan (Altitude & Speed Filtered)

## 1. Overview & Goal

- **Airport**: Gdańsk Lech Wałęsa Airport (GDN / EPGD)
- **Challenge**: Frequent **GNSS / GPS Jamming in the Baltic region** causes aircraft to transmit Mode-S data without GPS coordinates (`lat`/`lon` missing).
- **Strategy**: 100% Coordinate-Free Filter using only **Altitude**, **Ground/Indicated Speed**, and **Vertical Rate**.
- **Storage Strategy**: Dual RAM/Disk RRD database (`tmpfs` in RAM at `/run/collectd/localhost/dump1090-localhost/dump1090_traffic-*.rrd`), zero SQL database overhead.

---

## 2. Coordinate-Free Filter Criteria

The `traffic.py` collectd plugin in `/usr/share/graphs1090/traffic.py` evaluates `/run/readsb/aircraft.json` every 60 seconds:

- **Altitude Window**: `alt <= 3,000 ft AMSL` (EPGD elevation is 489 ft; final approach & initial climb occur below 3,000 ft).
- **Speed Window**: `95 kts <= speed <= 210 kts` (Commercial transport category aircraft approach/departure speed; filters out light GA circuits and slow helicopters).
- 🛬 **Landings (Arrivals)**: `baro_rate < -200 fpm` (descending).
- 🛫 **Departures**: `baro_rate > +200 fpm` (climbing).
- **De-duplication**: 15-minute (`900s`) cooldown per aircraft ICAO hex code.

---

## 3. RRD Storage & Graph Smoothing

- **RAM RRD Path**: `/run/collectd/localhost/dump1090-localhost/dump1090_traffic-landings.rrd` & `dump1090_traffic-departures.rrd`
- **Graph Math ([`stat1090.sh`](file:///home/yk/proj/stat1090/stat1090.sh#L430-L435))**:
  - `CDEF:landings_rate=landings_raw,60,*`
  - `CDEF:landings=landings_rate,3600,TRENDNAN` (1-hour moving average filter for accurate hourly flight numbers).
