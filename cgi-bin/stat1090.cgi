#!/bin/bash
# stat1090 CGI graph handler
# Parses QUERY_STRING for type, from, and till parameters

renice 20 $$ &>/dev/null || true

# Parse query string parameters
saveIFS=$IFS
IFS='&'
for param in $QUERY_STRING; do
    case "$param" in
        type=*) TYPE="${param#*=}" ;;
        graph=*) TYPE="${param#*=}" ;;
        from=*) FROM="${param#*=}" ;;
        till=*) TILL="${param#*=}" ;;
        host=*) HOST="${param#*=}" ;;
    esac
done
IFS=$saveIFS

# URL decoding helper
urldecode() {
    local url_encoded="${1//+/ }"
    printf '%b' "${url_encoded//%/\\x}"
}

TYPE=$(urldecode "${TYPE:-aircraft}")
FROM=$(urldecode "${FROM:-24h}")
TILL=$(urldecode "${TILL:-now}")
HOST=$(urldecode "${HOST:-localhost}")

# Sanitize inputs
TYPE=$(echo "$TYPE" | tr -cd 'a-zA-Z0-9_')
FROM=$(echo "$FROM" | tr -cd 'a-zA-Z0-9:\-\+.')
TILL=$(echo "$TILL" | tr -cd 'a-zA-Z0-9:\-\+.')
HOST=$(echo "$HOST" | tr -cd 'a-zA-Z0-9._\-')

TMP_PNG="/tmp/stat1090_cgi_${RANDOM}_${RANDOM}.png"
STAT_SH="/usr/share/stat1090/stat1090.sh"
if [[ ! -f "$STAT_SH" ]]; then
    STAT_SH="$(dirname "$(realpath "$0")")/../stat1090.sh"
fi

bash "$STAT_SH" "$TYPE" "$TMP_PNG" "$FROM" "$TILL" "$HOST" &>/dev/null

if [[ -f "$TMP_PNG" ]]; then
    SIZE=$(stat -c%s "$TMP_PNG" 2>/dev/null || wc -c < "$TMP_PNG")
    echo "Content-Type: image/png"
    echo "Content-Length: $SIZE"
    echo "Cache-Control: no-cache, no-store, must-revalidate"
    echo ""
    cat "$TMP_PNG"
    rm -f "$TMP_PNG"
else
    echo "Status: 500 Internal Error"
    echo "Content-Type: text/plain"
    echo ""
    echo "Error generating graph"
fi
