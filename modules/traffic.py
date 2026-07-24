try:
    import collectd
except ImportError:
    class DummyCollectd:
        def warning(self, msg): print("COLLECTD WARNING:", msg)
        def Values(self, **kwargs): return self
        def dispatch(self, **kwargs): pass
        def register_read(self, func, interval=60): pass
    collectd = DummyCollectd()
import json
import time
import os
import configparser

ACTIVE_LANDINGS = {}    # { hex: timestamp }
ACTIVE_DEPARTURES = {}  # { hex: timestamp }

CONFIG_PATH = "/etc/default/stat1090.cfg"

def load_config():
    config = {
        "min_speed": 125,
        "max_speed": 250,
        "min_rate": 200,
        "max_alt": 4500,
        "filter_commercial_prefixes": False,
        "commercial_prefixes": {"RYR", "WZZ", "LOT", "DLH", "KLM", "SAS", "ENT", "EWG", "TVP", "SDM", "AFR", "BAW", "FIN", "AEE", "LGL", "AUA", "SWR", "TAP", "IBE", "WUK", "TRA", "PBD"},
        "allowed_categories": {"A2", "A3", "A4", "A5"}
    }
    if os.path.exists(CONFIG_PATH):
        try:
            parser = configparser.ConfigParser()
            parser.read(CONFIG_PATH)
            if parser.has_section("traffic"):
                sec = parser["traffic"]
                config["min_speed"] = sec.getint("min_speed", config["min_speed"])
                config["max_speed"] = sec.getint("max_speed", config["max_speed"])
                config["min_rate"] = sec.getint("min_rate", config["min_rate"])
                config["max_alt"] = sec.getint("max_alt", config["max_alt"])
                config["filter_commercial_prefixes"] = sec.getboolean("filter_commercial_prefixes", config["filter_commercial_prefixes"])
                
                prefixes = sec.get("commercial_prefixes", "")
                if prefixes:
                    config["commercial_prefixes"] = {p.strip().upper() for p in prefixes.split(",") if p.strip()}
                    
                categories = sec.get("allowed_categories", "")
                if categories and categories.strip().upper() != "ALL":
                    config["allowed_categories"] = {c.strip().upper() for c in categories.split(",") if c.strip()}
                else:
                    config["allowed_categories"] = None
        except Exception as e:
            collectd.warning("traffic plugin: error parsing config %s: %s" % (CONFIG_PATH, str(e)))
    return config

def read_traffic(data=None):
    now = time.time()
    landings = 0
    departures = 0
    
    cfg = load_config()
    min_spd = cfg["min_speed"]
    max_spd = cfg["max_speed"]
    min_rt = cfg["min_rate"]
    max_alt = cfg["max_alt"]
    filter_pfx = cfg["filter_commercial_prefixes"]
    allowed_pfx = cfg["commercial_prefixes"]
    allowed_cat = cfg["allowed_categories"]

    # Locate aircraft.json
    data_path = "/run/readsb/aircraft.json"
    if not os.path.exists(data_path):
        data_path = "/run/dump1090-fa/aircraft.json"
    if not os.path.exists(data_path):
        data_path = "/usr/share/graphs1090/data-symlink/aircraft.json"
        
    aircraft_list = []
    if os.path.exists(data_path):
        try:
            with open(data_path, "r") as f:
                aircraft_data = json.load(f)
                aircraft_list = aircraft_data.get("aircraft", [])
        except Exception as e:
            collectd.warning("traffic plugin: error reading %s: %s" % (data_path, str(e)))

    # Clean up stale cooldowns (> 15 minutes / 900 seconds)
    for h in list(ACTIVE_LANDINGS.keys()):
        if now - ACTIVE_LANDINGS[h] > 900:
            del ACTIVE_LANDINGS[h]
    for h in list(ACTIVE_DEPARTURES.keys()):
        if now - ACTIVE_DEPARTURES[h] > 900:
            del ACTIVE_DEPARTURES[h]

    for ac in aircraft_list:
        hex_code = ac.get("hex")
        if not hex_code:
            continue
            
        alt = ac.get("alt_baro", ac.get("alt_geom"))
        if alt is None or alt == "ground" or alt > max_alt:
            continue
            
        speed = ac.get("gs", ac.get("ias", 0))
        if speed < min_spd or speed > max_spd:
            continue

        rate = ac.get("baro_rate", ac.get("geom_rate", 0))
        if abs(rate) < min_rt:
            continue

        # Emitter Category filter
        cat = ac.get("category")
        if allowed_cat is not None and cat:
            if cat.upper() not in allowed_cat:
                continue

        # Commercial Prefix filter
        flight = ac.get("flight", "").strip().upper()
        if filter_pfx and allowed_pfx:
            pfx = flight[:3] if len(flight) >= 3 else ""
            if pfx not in allowed_pfx:
                continue

        if rate < -min_rt:  # Final approach descending
            if hex_code not in ACTIVE_LANDINGS:
                ACTIVE_LANDINGS[hex_code] = now
                landings += 1
                try:
                    with open('/tmp/stat1090_traffic.log', 'a') as f:
                        f.write(f"{now}: LANDING {hex_code} {flight} alt={alt} spd={speed} rate={rate} cat={cat}\n")
                except: pass
        elif rate > min_rt: # Initial climb departing
            if hex_code not in ACTIVE_DEPARTURES:
                ACTIVE_DEPARTURES[hex_code] = now
                departures += 1
                try:
                    with open('/tmp/stat1090_traffic.log', 'a') as f:
                        f.write(f"{now}: DEPARTURE {hex_code} {flight} alt={alt} spd={speed} rate={rate} cat={cat}\n")
                except: pass

    # Dispatch to collectd
    val = collectd.Values(host='', plugin='dump1090', plugin_instance='localhost', type='dump1090_ops', time=0)
    val.dispatch(type_instance='landings', values=[landings])
    val.dispatch(type_instance='departures', values=[departures])

collectd.register_read(read_traffic, interval=60)
