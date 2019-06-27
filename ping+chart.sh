#!/bin/bash

to_script() {
  awk "/^ping $IP_FILTER .*$/ {if (\$$COLUMN_ID) print \$2 \"=\" \$$COLUMN_ID}" | xargs echo a
}

read_ping() {
  # read statistics store
  while read STAT_FILE; do
    cat $STAT_FILE | to_script
  done < <(find statistics -type f | sort | head -n-1 | tail -n $(tput cols))
  echo g
  # read incremental log
  while read LINE; do
    if [[ "$LINE" =~ ^.*saved.\((.*)\).*$ ]]; then
      cat ${BASH_REMATCH[1]} | to_script
      echo g
    fi
  done
}

case "$1" in
  -h|--help)
    echo >&2 "Usage: $0 [-h | -f] [<column>] [<addr-filter>]"
    exit
    ;;
  -f|follow)
    FOLLOW_FILE="$2"
    shift
    shift
    ;;
esac

if [ -n "$1" ]; then
  case "$1" in
    x|sent)
      COLUMN_ID=3
      ;;
    r|receive)
      COLUMN_ID=4
      ;;
    q|loss)
      COLUMN_ID=5
      ;;
    a|min)
      COLUMN_ID=6
      ;;
    v|avg)
      COLUMN_ID=7
      ;;
    b|max)
      COLUMN_ID=8
      ;;
    k|mdev)
      COLUMN_ID=9
      ;;
    [3-9])
      COLUMN_ID=$1
      ;;
    *)
      echo >&2 "Unknown column '$1'."
      exit -1
      ;;
  esac
else
  COLUMN_ID=5
fi
IP_FILTER=${2:-'.*'}

if [ -z "$FOLLOW_FILE" ]; then
  bash ping.sh | read_ping | bash chart.sh
else
  tail -n0 -f $FOLLOW_FILE | read_ping | bash chart.sh
fi
