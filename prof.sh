#!/bin/bash

##################
# Profiling Tool #
##################

SCRIPT_FILE=$1
shift

LOG_FILE="$(mktemp).log"
echo >&2 "Logging to $LOG_FILE..."

# execute script
PS4='\n# ${BASH_SOURCE} ${LINENO} ${FUNCNAME[0]}() -- ' bash -x "$SCRIPT_FILE" "$@" 1>&2 2>$LOG_FILE

declare -A HIT_MAP=()

while IFS=' ' read LINE_NO COUNT; do
  HIT_MAP[$LINE_NO]=$COUNT
done < <(cat $LOG_FILE | grep -E "^# $SCRIPT_FILE" | cut -d' ' -f3 | sort | uniq -c | awk '{print $2 " " $1}')

while IFS=$'\t' read LINE_NO TEXT; do
  HIT_COUNT=${HIT_MAP[$(tr -d ' ' <<< "$LINE_NO")]}
  if [ -n "$HIT_COUNT" ]; then
    printf "%-67s # %d hit(s)\n" "$TEXT" "$HIT_COUNT"
  else
    echo "$TEXT"
  fi
done < <(cat -n $SCRIPT_FILE)
