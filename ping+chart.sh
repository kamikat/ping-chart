#!/bin/bash

source chart.sh

to_script() {
  awk "/^ping $IP_FILTER .*$/ {if (\$$COLUMN_ID!=\"\") print \$2 \"=\" \$$COLUMN_ID}" | xargs echo a
}

read_ping() {
  # read statistics store
  if [ ! -n "$NO_HISTORY" ]; then
    while read STAT_FILE; do
      cat $STAT_FILE | to_script
    done < <(find statistics -type f | sort -r | tail -n+2 | head -n $(tput cols) | tac)
    echo g
  fi
  # read incremental log
  while read LINE; do
    if [[ "$LINE" =~ ^.*saved.\((.*)\).*$ ]]; then
      cat ${BASH_REMATCH[1]} | to_script
      echo g
    fi
  done
}

INPUT_COMMAND="bash ping.sh"
CHART_COMMAND="to_chart"

while true; do
  case "$1" in
    -h|--help)
      echo >&2 "Usage: $0 [-h] [-f|-q] [-c] [-r] [<column>] [<addr-filter>]"
      exit
      ;;
    -f|--follow)
      INPUT_COMMAND="tail -n0 -f $2"
      shift
      ;;
    -q|--quiet)
      INPUT_COMMAND="echo"
      ;;
    -c|--clear)
      NO_HISTORY=1
      ;;
    -r|--raw)
      CHART_COMMAND=cat
      ;;
    *)
      break
      ;;
  esac
  shift
done

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

$INPUT_COMMAND | read_ping | $CHART_COMMAND
