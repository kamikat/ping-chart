#!/bin/bash

source chart.sh

read_ping() {
  # read statistics store
  if [ ! -n "$NO_HISTORY" ]; then
    while read STAT_FILES; do
      cat $STAT_FILES | awk "$AWK_PROG" | xargs echo a
    done < <(find statistics -type f | sort -r | tail -n+2 | head -n $((HISTORY_COUNT * BATCH_SIZE)) | tac | xargs -n $BATCH_SIZE)
    echo g
  fi
  # read incremental log
  while read LINE; do
    if [[ "$LINE" =~ ^.*saved.\((.*)\).*$ ]]; then
      cat ${BASH_REMATCH[1]} | awk "$AWK_PROG" | xargs echo a
      echo g
    fi
  done
}

INPUT_COMMAND="bash ping.sh"
CHART_COMMAND="to_chart"
HISTORY_COUNT="$(tput cols)"
BATCH_SIZE=1

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
    -r|--raw)
      CHART_COMMAND=cat
      ;;
    -b|--batch)
      INPUT_COMMAND="echo"
      BATCH_SIZE=$2
      shift
      ;;
    -B|--batch-method)
      BATCH_METHOD=$2
      shift
      ;;
    -h|--history)
      HISTORY_COUNT=$2
      shift
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
    k|stddev|mdev)
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

get_prog() {
  K="\$2"
  V="\$$COLUMN_ID"
  case $1 in
    min)
      ROW_STMT="min[$K] = (min[$K] != \"\" && min[$K] < $V ? min[$K] : $V)"
      END_STMT="for (key in min) { print key \"=\" min[key] }"
      ;;
    max)
      ROW_STMT="max[$K] = (max[$K] != \"\" && max[$K] > $V ? max[$K] : $V)"
      END_STMT="for (key in max) { print key \"=\" max[key] }"
      ;;
    avg|average|mean)
      ROW_STMT="sum[$K] += $V; count[$K]++;"
      END_STMT="for (key in sum) { print key \"=\" (sum[key] / count[key]) }"
      ;;
  esac
  echo "/^ping $IP_FILTER .*$/ { if ($V!=\"\") { $ROW_STMT } } END { $END_STMT }"
}

AWK_PROG=$(get_prog ${BATCH_METHOD:-max})

$INPUT_COMMAND | read_ping | $CHART_COMMAND
