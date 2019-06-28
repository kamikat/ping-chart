#!/bin/bash

SERVER_FILE=${SERVER_FILE:-servers.lst}
STAT_DIR=${STAT_DIR:-statistics}
PROG_PARSE_1='s@PING ([0-9.]+).*--- ([0-9]+) packets transmitted, ([0-9]+) .*, ([0-9.]+)%.*= ([0-9.]+)/([0-9.]+)/([0-9.]+)/([0-9.]+).*$@ping \1 \2 \3 \4 \5 \6 \7 \8@g'
PROG_PARSE_2='s@PING ([0-9.]+).*--- ([0-9]+) packets transmitted, ([0-9]+) .*, ([0-9.]+)%.*$@ping \1 \2 \3 \4@g' # in case of 100% packet loss

structured_ping() {
  timeout --foreground -s INT $PING_INTERVAL ping -q $@ | xargs | sed -E "$PROG_PARSE_1" | sed -E "$PROG_PARSE_2"
}

PING_INTERVAL=${1:-60}
shift

while true; do
  SERVER_LIST="$(cat $SERVER_FILE 2>/dev/null | cut -f1)"
  if [ -z "$SERVER_LIST" ]; then
    cat >&2 << ERROR
ERROR: Cannot read server list from '$SERVER_FILE'.
ERROR
    exit -1
  fi
  STAT_FILE=$STAT_DIR/$(date +%Y%m%d/%H%M%S)
  mkdir -p $(dirname $STAT_FILE)
  echo "Pinging $(wc -l <<< "$SERVER_LIST" | tr -d ' ') server(s) for $PING_INTERVAL seconds..."
  for SERVER_ADDR in $SERVER_LIST; do
    structured_ping $@ $SERVER_ADDR >>$STAT_FILE &
  done
  wait
  echo "$(wc -l < $STAT_FILE | tr -d ' ') ping statistics saved ($STAT_FILE)."
done
