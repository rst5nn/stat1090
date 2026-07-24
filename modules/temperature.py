try:
    import collectd
except ImportError:
    class _Dummy:
        def warning(self, m): print("COLLECTD WARNING:", m)
        def Values(self, **kw): return self
        def dispatch(self, **kw): pass
        def register_read(self, f, interval=60): pass
    collectd = _Dummy()

import os
import glob

def read_temperature(data=None):
    """Read all thermal zones and dispatch temperature in degrees Celsius."""
    zones = sorted(glob.glob("/sys/class/thermal/thermal_zone*/temp"))
    for zone_path in zones:
        zone_dir = os.path.dirname(zone_path)
        zone_name = os.path.basename(zone_dir)
        type_path = os.path.join(zone_dir, "type")
        try:
            with open(type_path) as f:
                zone_type = f.read().strip().replace("-", "_")
        except Exception:
            zone_type = zone_name

        try:
            with open(zone_path) as f:
                temp_milli = int(f.read().strip())
        except Exception:
            continue

        val = collectd.Values(
            host='', plugin='stat1090', plugin_instance='localhost',
            type='temperature', type_instance=zone_type, time=0
        )
        val.dispatch(values=[temp_milli / 1000.0])

collectd.register_read(read_temperature, interval=60)
