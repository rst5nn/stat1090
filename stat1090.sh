#!/bin/bash
# stat1090 graph generator script
# Supports exact time range filtering via FROM and TILL parameters
# Graphs supported: range, signal, aircraft

renice -n 20 -p $$ &>/dev/null || true

DB="/var/lib/collectd/rrd"
if [[ -d /run/collectd/localhost ]]; then
    DB="/run/collectd"
fi

# Load config if present
if [[ -f /etc/default/stat1090 ]]; then
    source /etc/default/stat1090
fi

# Default graph dimensions
width=${GRAPH_WIDTH:-1100}
height=${GRAPH_HEIGHT:-340}
colorscheme="${7:-${GRAPH_COLOR_SCHEME:-dark}}"

if [[ "$colorscheme" == "bright" ]]; then
    colorscheme="light"
fi

# Color palette definition
CANVAS="18191c"
BACK="222428"
FONT="e1e4e8"
AXIS="8b949e"
FRAME="30363d"
GRID="2d333b"
MGRID="444c56"

# Dark Theme Color Palette (Antigravity Design Expert)
NOISE_FILL="1c3d2e"
NOISE_LINE="34d399"
PEAK_SIGNAL="f43f5e"
MEDIAN_SIGNAL="38bdf8"
MIN_SIGNAL="fbbf24"
AIRCRAFT_AREA="1c3d2e"
AREA_FILL_PRIMARY="1c3d2e"
ADSB_POS_LINE="38bdf8"
MAX_RANGE_LINE="38bdf8"
CLOSEST_DIST="f43f5e"
MEDIAN_DIST="fbbf24"
PEAK_RANGE="818cf8"

LGREEN="1db992"
DGREEN="5cb85c"
GREEN="386619"

LBLUE="7fc7ff"
BLUE="38bdf8"
ABLUE="0c5685"
DBLUE="0033AA"

LCYAN="29a7e6"
CYAN="38bdf8"

RED="f43f5e"
DRED="990000"
LIGHTYELLOW="FFFF99"
AGRAY="444444"
INDIGO="818cf8"
SILVER="888888"
ROSE="f43f5e"
AMBER="fbbf24"

if [[ "$colorscheme" == "light" ]]; then
    CANVAS="FFFFFF"
    BACK="F8F9FA"
    FONT="212529"
    AXIS="495057"
    FRAME="CED4DA"
    GRID="E9ECEF"
    MGRID="DEE2E6"

    # Light Theme Color Palette
    NOISE_FILL="E6F4EA"
    NOISE_LINE="10B981"
    PEAK_SIGNAL="E11D48"
    MEDIAN_SIGNAL="0284C7"
    MIN_SIGNAL="D97706"
    AIRCRAFT_AREA="E6F4EA"
    AREA_FILL_PRIMARY="E6F4EA"
    ADSB_POS_LINE="0284C7"
    MAX_RANGE_LINE="0284C7"
    CLOSEST_DIST="E11D48"
    MEDIAN_DIST="D97706"
    PEAK_RANGE="4F46E5"

    LGREEN="7de87d"
    GREEN="32CD32"
    DGREEN="228B22"
    BLUE="0284C7"
    RED="E11D48"
fi

COLORS=(
    -c "CANVAS#$CANVAS"
    -c "BACK#$BACK"
    -c "FONT#$FONT"
    -c "AXIS#$AXIS"
    -c "FRAME#$FRAME"
    -c "GRID#$GRID"
    -c "MGRID#$MGRID"
    -c "SHADEA#$BACK"
    -c "SHADEB#$BACK"
)

# Helper for missing rrd files
EMPTY_RRD="/var/lib/stat1090/empty.rrd"
if ! mkdir -p "$(dirname "$EMPTY_RRD")" &>/dev/null; then
    EMPTY_RRD="/tmp/stat1090/empty.rrd"
    mkdir -p "$(dirname "$EMPTY_RRD")" &>/dev/null || true
fi

if [[ ! -f "$EMPTY_RRD" ]]; then
    if command -v rrdtool &>/dev/null; then
        rrdtool create "$EMPTY_RRD" --step 60 DS:value:GAUGE:120:U:U RRA:AVERAGE:0.5:1:2880 RRA:MAX:0.5:1:2880 &>/dev/null || true
    fi
fi

check_rrd() {
    if [[ -f "$1" ]]; then
        echo "$1"
    else
        echo "$EMPTY_RRD"
    fi
}

# Parse parameters
# Usage: stat1090.sh <graph_type> <output_png> <from_val> <till_val> [hostname] [db_dir]
TYPE="${1:-aircraft}"
OUT_FILE="${2:-/tmp/stat1090_out.png}"
FROM_VAL="${3:-24h}"
TILL_VAL="${4:-now}"
HOST_NAME="${5:-localhost}"
CUSTOM_DB="${6:-$DB}"

DB_DIR="${CUSTOM_DB}/${HOST_NAME}/dump1090-${HOST_NAME}"
if [[ ! -d "$DB_DIR" ]]; then
    # Fallback search for any dump1090 folder
    FOUND_DB=$(find "$CUSTOM_DB" -maxdepth 2 -type d -name "dump1090-*" | head -n 1)
    if [[ -n "$FOUND_DB" ]]; then
        DB_DIR="$FOUND_DB"
    fi
fi

parse_time() {
    local val="$1"
    local default_val="$2"
    if [[ -z "$val" ]]; then
        echo "$default_val"
        return
    fi
    if [[ "$val" =~ ^[0-9]+[smhdwy]$ ]]; then
        echo "end-$val"
        return
    fi
    local epoch
    epoch=$(date -d "$val" +%s 2>/dev/null || date -d "${val/T/ }" +%s 2>/dev/null)
    if [[ -n "$epoch" ]]; then
        echo "$epoch"
    else
        echo "$default_val"
    fi
}

START_VAL=$(parse_time "$FROM_VAL" "end-24h")
END_VAL=$(parse_time "$TILL_VAL" "now")

START_OPT=("--start" "$START_VAL")
END_OPT=("--end" "$END_VAL")

TMP_OUT="${OUT_FILE}.tmp.$RANDOM"
NOW_STR=$(date "+%Y-%m-%d %H:%M:%S %Z")

case "$TYPE" in
    aircraft|"aircraft_seen")
        # ADS-B Aircraft Tracked
        rrdtool graph \
            "$TMP_OUT" \
            "${START_OPT[@]}" \
            "${END_OPT[@]}" \
            --width "$width" \
            --height "$height" \
            "${COLORS[@]}" \
            --title "ADS-B Aircraft Tracked" \
            --vertical-label "Aircraft Count" \
            --right-axis 1:0 \
            --right-axis-label "Aircraft Count" \
            --lower-limit 0 \
            --units-exponent 0 \
            "TEXTALIGN:center" \
            "DEF:all=$(check_rrd "$DB_DIR/dump1090_aircraft-recent.rrd"):total:AVERAGE" \
            "DEF:all_max=$(check_rrd "$DB_DIR/dump1090_aircraft-recent.rrd"):total:MAX" \
            "DEF:pos=$(check_rrd "$DB_DIR/dump1090_aircraft-recent.rrd"):positions:AVERAGE" \
            "DEF:mlat=$(check_rrd "$DB_DIR/dump1090_mlat-recent.rrd"):value:AVERAGE" \
            "DEF:tisb=$(check_rrd "$DB_DIR/dump1090_tisb-recent.rrd"):value:AVERAGE" \
            "DEF:rgps=$(check_rrd "$DB_DIR/dump1090_gps-recent.rrd"):value:AVERAGE" \
            "CDEF:tisb0=tisb,UN,0,tisb,IF" \
            "CDEF:noloc=all,pos,-" \
            "CDEF:cgps=pos,tisb0,-,mlat,-" \
            "CDEF:gps=rgps,UN,cgps,rgps,IF" \
            "VDEF:avgac=all,AVERAGE" \
            "VDEF:maxac=all_max,MAXIMUM" \
            "AREA:all#$AREA_FILL_PRIMARY" \
            "LINE1.5:all#$NOISE_LINE:Aircraft Tracked   " \
            "GPRINT:avgac:Avg\:%3.0lf   " \
            "GPRINT:maxac:Max\:%3.0lf   " \
            "LINE1.5:gps#$ADSB_POS_LINE:w/ ADS-B pos.\c" \
            --watermark "stat1090 | Rendered: $NOW_STR" &>/dev/null
        ;;

    range|"adsb_range")
        # ADS-B Range Graph
        unitconv=0.000539956803 # default Nautical Miles
        label="Nautical Miles"
        shortlabel="NM"
        if [[ "${RANGE_UNIT:-nautical}" == "statute" ]]; then
            unitconv=0.000621371
            label="Statute Miles"
            shortlabel="mi"
        elif [[ "${RANGE_UNIT:-nautical}" == "metric" ]]; then
            unitconv=0.001
            label="Kilometers"
            shortlabel="km"
        fi

        rrdtool graph \
            "$TMP_OUT" \
            "${START_OPT[@]}" \
            "${END_OPT[@]}" \
            --width "$width" \
            --height "$height" \
            "${COLORS[@]}" \
            --slope-mode \
            --title "ADS-B Max Range ($label)" \
            --vertical-label "$label" \
            --right-axis 1:0 \
            --right-axis-label "$label" \
            --units-exponent 0 \
            --lower-limit 0 \
            "TEXTALIGN:center" \
            "DEF:drange=$(check_rrd "$DB_DIR/dump1090_range-max_range.rrd"):value:MAX" \
            "DEF:drange_a=$(check_rrd "$DB_DIR/dump1090_range-max_range.rrd"):value:AVERAGE" \
            "DEF:dmin=$(check_rrd "$DB_DIR/dump1090_range-minimum.rrd"):value:MIN" \
            "DEF:dmedian=$(check_rrd "$DB_DIR/dump1090_range-median.rrd"):value:AVERAGE" \
            "CDEF:range=drange,$unitconv,*" \
            "CDEF:range_a=drange_a,$unitconv,*" \
            "CDEF:min=dmin,$unitconv,*" \
            "CDEF:median=dmedian,$unitconv,*" \
            "VDEF:avgrange=range_a,AVERAGE" \
            "VDEF:peakrange=range,MAXIMUM" \
            "LINE1.5:range#$MAX_RANGE_LINE:Max Range " \
            "LINE1:peakrange#$PEAK_RANGE:Max Dist:dashes" \
            "GPRINT:peakrange:%1.0lf $shortlabel   " \
            "LINE1:avgrange#$SILVER:Avg:dashes" \
            "GPRINT:avgrange:%1.0lf $shortlabel   " \
            "LINE1.5:min#$CLOSEST_DIST:Closest " \
            "GPRINT:min:MIN:%4.1lf $shortlabel   " \
            "LINE1.5:median#$MEDIAN_DIST:Median " \
            "GPRINT:median:AVERAGE:%4.1lf $shortlabel\c" \
            --watermark "stat1090 | Rendered: $NOW_STR" &>/dev/null
        ;;

    signal|"signal_level")
        # ADS-B Signal Level Graph
        rrdtool graph \
            "$TMP_OUT" \
            "${START_OPT[@]}" \
            "${END_OPT[@]}" \
            --width "$width" \
            --height "$height" \
            "${COLORS[@]}" \
            --title "ADS-B Signal Level" \
            --vertical-label "dBFS" \
            --right-axis 1:0 \
            --right-axis-label "dBFS" \
            --units-exponent 0 \
            --upper-limit 3 \
            --lower-limit -45 \
            --rigid \
            "TEXTALIGN:center" \
            "DEF:signal=$(check_rrd "$DB_DIR/dump1090_dbfs-signal.rrd"):value:AVERAGE" \
            "DEF:min=$(check_rrd "$DB_DIR/dump1090_dbfs-min_signal.rrd"):value:MIN" \
            "DEF:median=$(check_rrd "$DB_DIR/dump1090_dbfs-median.rrd"):value:AVERAGE" \
            "DEF:peak=$(check_rrd "$DB_DIR/dump1090_dbfs-peak_signal.rrd"):value:MAX" \
            "DEF:noise=$(check_rrd "$DB_DIR/dump1090_dbfs-noise.rrd"):value:AVERAGE" \
            "DEF:msg_local=$(check_rrd "$DB_DIR/dump1090_messages-local_accepted.rrd"):value:AVERAGE" \
            "DEF:msg_remote=$(check_rrd "$DB_DIR/dump1090_messages-remote_accepted.rrd"):value:AVERAGE" \
            "DEF:strong=$(check_rrd "$DB_DIR/dump1090_messages-strong_signals.rrd"):value:AVERAGE" \
            "CDEF:messages=msg_local,msg_remote,ADDNAN" \
            "VDEF:strong_total=strong,TOTAL" \
            "VDEF:messages_total=messages,TOTAL" \
            "CDEF:hundred=messages,UN,100,100,IF" \
            "CDEF:strong_percent=strong_total,hundred,*,messages_total,/" \
            "VDEF:strong_percent_vdef=strong_percent,LAST" \
            "CDEF:mes=median,UN,signal,median,IF" \
            "CDEF:bot=noise,UN,-45,-45,IF" \
            "CDEF:noise_area=noise,45,+" \
            "AREA:bot#$CANVAS" \
            "AREA:noise_area#$AREA_FILL_PRIMARY:STACK" \
            "LINE1.5:peak#$PEAK_SIGNAL:Peak Signal   " \
            "LINE1.5:mes#$MEDIAN_SIGNAL:Median Signal   " \
            "LINE1.5:min#$MIN_SIGNAL:Min Signal   " \
            "LINE1.5:noise#$NOISE_LINE:Noise Floor   " \
            "HRULE:-3#$SILVER:-3dBFS   :dashes=5,5" \
            "GPRINT:strong_percent_vdef:Messages > -3dBFS\:%1.1lf%% of messages\c" \
            --watermark "stat1090 | Rendered: $NOW_STR" &>/dev/null
        ;;

    messages|"message_rate"|"messages_received")
        # Message Rate Graph
        rrdtool graph \
            "$TMP_OUT" \
            "${START_OPT[@]}" \
            "${END_OPT[@]}" \
            --width "$width" \
            --height "$height" \
            "${COLORS[@]}" \
            --slope-mode \
            --title "Message Rate" \
            --vertical-label "Messages/Second" \
            --right-axis 1:0 \
            --right-axis-label "Messages/Second" \
            --units-exponent 0 \
            --lower-limit 0 \
            "TEXTALIGN:center" \
            "DEF:msg_local=$(check_rrd "$DB_DIR/dump1090_messages-local_accepted.rrd"):value:AVERAGE" \
            "DEF:msg_local_max=$(check_rrd "$DB_DIR/dump1090_messages-local_accepted.rrd"):value:MAX" \
            "DEF:msg_remote=$(check_rrd "$DB_DIR/dump1090_messages-remote_accepted.rrd"):value:AVERAGE" \
            "DEF:msg_remote_max=$(check_rrd "$DB_DIR/dump1090_messages-remote_accepted.rrd"):value:MAX" \
            "DEF:strong=$(check_rrd "$DB_DIR/dump1090_messages-strong_signals.rrd"):value:AVERAGE" \
            "CDEF:messages=msg_local,msg_remote,ADDNAN" \
            "CDEF:messages_max=msg_local_max,msg_remote_max,ADDNAN" \
            "VDEF:avgmsg=messages,AVERAGE" \
            "VDEF:maxmsg=messages_max,MAXIMUM" \
            "VDEF:strong_total=strong,TOTAL" \
            "VDEF:messages_total=messages,TOTAL" \
            "CDEF:hundred=messages,UN,100,100,IF" \
            "CDEF:strong_percent=strong_total,hundred,*,messages_total,/" \
            "VDEF:strong_percent_vdef=strong_percent,LAST" \
            "AREA:messages#$GREEN:Messages Received   " \
            "LINE1:messages#$EMERALD" \
            "GPRINT:avgmsg:Avg\:%3.0lf msgs/s   " \
            "GPRINT:maxmsg:Max\:%3.0lf msgs/s   " \
            "AREA:strong#$ROSE:Messages > -3dBFS" \
            "GPRINT:strong_percent_vdef: (%1.1lf%% of messages)\c" \
            --watermark "stat1090 | Rendered: $NOW_STR" &>/dev/null
        ;;

    tracks|"tracks_seen"|"adsb_tracks_seen")
        # ADS-B Tracks Seen Graph (8 minute exp. moving avg.)
        rrdtool graph \
            "$TMP_OUT" \
            "${START_OPT[@]}" \
            "${END_OPT[@]}" \
            --width "$width" \
            --height "$height" \
            "${COLORS[@]}" \
            --slope-mode \
            --title "ADS-B Tracks Seen" \
            --vertical-label "Tracks/Hour" \
            --right-axis 1:0 \
            --right-axis-label "Tracks/Hour" \
            --units-exponent 0 \
            --lower-limit 0 \
            "TEXTALIGN:center" \
            "DEF:all=$(check_rrd "$DB_DIR/dump1090_tracks-all.rrd"):value:AVERAGE" \
            "DEF:single=$(check_rrd "$DB_DIR/dump1090_tracks-single_message.rrd"):value:AVERAGE" \
            "CDEF:s=single,3600,*" \
            "CDEF:m=all,3600,*,s,-" \
            "CDEF:s8=s,480,TRENDNAN,4.1,*" \
            "CDEF:m8=m,480,TRENDNAN,4.1,*" \
            "CDEF:s4=s,240,TRENDNAN,2.6,*" \
            "CDEF:m4=m,240,TRENDNAN,2.6,*" \
            "CDEF:s2=s,120,TRENDNAN,1.6,*" \
            "CDEF:m2=m,120,TRENDNAN,1.6,*" \
            "CDEF:s1=s,60,TRENDNAN" \
            "CDEF:m1=m,60,TRENDNAN" \
            "CDEF:s_ema=s8,s4,+,s2,+,s1,+,9.3,/" \
            "CDEF:m_ema=m8,m4,+,m2,+,m1,+,9.3,/" \
            "VDEF:avg_m=m_ema,AVERAGE" \
            "VDEF:max_m=m_ema,MAXIMUM" \
            "VDEF:avg_s=s_ema,AVERAGE" \
            "VDEF:max_s=s_ema,MAXIMUM" \
            "AREA:m_ema#$GREEN:> 1 message   " \
            "LINE1:m_ema#$EMERALD" \
            "GPRINT:avg_m:Avg\:%4.0lf/h   " \
            "GPRINT:max_m:Max\:%4.0lf/h   " \
            "AREA:s_ema#$CYAN:Single message:STACK" \
            "GPRINT:avg_s:Avg\:%4.0lf/h   " \
            "GPRINT:max_s:Max\:%4.0lf/h\c" \
            --watermark "stat1090 | Rendered: $NOW_STR" &>/dev/null
        ;;
    *)
        echo "Unknown graph type: $TYPE"
        exit 1
        ;;
esac

if [[ -f "$TMP_OUT" ]]; then
    mv "$TMP_OUT" "$OUT_FILE"
else
    echo "Failed to generate graph $TYPE"
    exit 1
fi
