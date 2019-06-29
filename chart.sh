#!/bin/bash

TERM_BG=${TERM_BG:-dark}

################
# Chart Styles #
################

STYLE_AXIS_RULER=$(tput sgr0)
STYLE_AXIS_LABEL=$(tput sgr0)
STYLE_LEGEND_LABEL=$(tput sgr0)

if [ $(tput colors) -ge 256 2>/dev/null ]; then
  CONTROL_SETAF='38;5;'
  rgb() {
    echo $((($1 * 6) / 256 * 36 + ($2 * 6) / 256 * 6 + ($3 * 6) / 256 + 16))
  }
else
  CONTROL_SETAF='9'
  rgb() {
    echo $(($3 / 128 * 4 + $2 / 128 * 2 + $1 / 128))
  }
fi

test_graph_style() {
  for I in $(seq 0 $((COLOR_SCHEME_SIZE - 1))); do
    echo -n "$(tput setab ${COLOR_SCHEME[$((($I) % $COLOR_SCHEME_SIZE))]})$(tput setaf 16) $I $(tput sgr0)"
  done
  echo
}

use_color_scheme() {
  declare -g -a COLOR_SCHEME=()
  while read R G B; do
    COLOR_SCHEME+=("$(rgb $R $G $B)")
  done
  COLOR_SCHEME_SIZE=${#COLOR_SCHEME[@]}
  [ -n "$DEBUG" ] && test_graph_style >&2
}

if [ -n "$COLOR_SCHEME" ]; then
  use_color_scheme <<< "$COLOR_SCHEME"
else
  if [ "$TERM_BG" != "light" ]; then
    # dark color scheme
    # h = 0 120 60 240 300 180 330 90 30 210 270 150
    # l = 0.69
    # s = 0.97
    use_color_scheme << RGB
253 99 99
99 253 99
253 253 99
99 99 253
253 99 253
99 253 253
253 99 176
176 253 99
253 176 99
99 176 253
176 99 253
99 253 176
RGB
  else
    # light color scheme
    # h = 0 120 240 330 30 210 270
    # l = 0.50
    # s = 0.90
    use_color_scheme << RGB
243 12 12
12 243 12
12 12 243
243 12 128
243 127 12
12 127 243
127 12 243
RGB
  fi
fi

put_graph_style() {
  CURRENT_COLOR=${COLOR_SCHEME[$(($1 % COLOR_SCHEME_SIZE))]}
  echo -n $'\e[0m\e['${CONTROL_SETAF}${CURRENT_COLOR}$'m'
}

#########
# Chart #
#########

to_chart() {
  WIDTH=${WIDTH:-auto}
  HEIGHT=${HEIGHT:-auto}
  MIN_Y=${MIN_Y:-auto}
  MAX_Y=${MAX_Y:-auto}
  MAX_HISTORY=${MAX_HISTORY:-300}

  PLOT_AXIS_WIDTH=${AXIS_WIDTH:-12}
  PLOT_PRECISION=${PLOT_PRECISION:-2}

  if [ "$MIN_Y" != "auto" ]; then
    PLOT_MIN_Y=$MIN_Y
  fi
  if [ "$MAX_Y" != "auto" ]; then
    PLOT_MAX_Y=$MAX_Y
  fi

  # setup series data store
  declare -A PLOT_SERIES
  declare -A PLOT_DATA
  PLOT_CURSOR_LAST=0
  repl
}

repl() {
  while read COMMAND SERIES_DATA; do
    case $COMMAND in
      a|append)
        # add to existing series data
        PLOT_CURSOR_LAST=$((PLOT_CURSOR_LAST + 1))
        ;;
      u|update)
        # change latest series data
        PLOT_CURSOR_LAST=$((PLOT_CURSOR_LAST))
        ;;
      g|plot)
        if [ "$WIDTH" == "auto" ]; then
          PLOT_WIDTH=$(tput cols)
        else
          PLOT_WIDTH=$WIDTH
        fi
        if [ "$HEIGHT" == "auto" ]; then
          PLOT_HEIGHT=$(($(tput lines) - 1))
        else
          PLOT_HEIGHT=$HEIGHT
        fi
        OUTPUT_BUFFER=$(plot)
        cat <<< "$OUTPUT_BUFFER$(tput sgr0)"
        unset OUTPUT_BUFFER
        continue
        ;;
      .|source)
        repl < "$SERIES_DATA"
        continue
        ;;
      r|resize)
        IFS=x read NEW_WIDTH NEW_HEIGHT
        WIDTH=$NEW_WIDTH
        HEIGHT=$NEW_HEIGHT
        continue
        ;;
      reset)
        unset PLOT_SERIES
        unset PLOT_DATA
        unset PLOT_CURSOR_LAST
        unset PLOT_MIN_Y PLOT_MAX_Y
        declare -A PLOT_SERIES
        declare -A PLOT_DATA
        continue
        ;;
      q|quit)
        break
        ;;
      *)
        echo "Command '$COMMAND' not found."
        continue
        ;;
    esac

    # update PLOT_SERIES definition
    for DATA_POINT in $SERIES_DATA; do
      IFS='=' read SERIES_NAME VALUE <<< "$DATA_POINT"
      if [ -z "${PLOT_SERIES[$SERIES_NAME]}" ]; then
        PLOT_SERIES[$SERIES_NAME]=${#PLOT_SERIES[@]}
      fi
      if [ "$MIN_Y" == "auto" ]; then
        if (( $(bc -l <<< "${PLOT_MIN_Y:-0} > $VALUE") )) || [ -z "$PLOT_MIN_Y" ]; then
          PLOT_MIN_Y=$VALUE
        fi
      fi
      if [ "$MAX_Y" == "auto" ]; then
        if (( $(bc -l <<< "${PLOT_MAX_Y:-0} < $VALUE") )) || [ -z "$PLOT_MAX_Y" ]; then
          PLOT_MAX_Y=$VALUE
        fi
      fi
    done

    # add series data
    PLOT_DATA[$PLOT_CURSOR_LAST]="$SERIES_DATA"

    # trim history to MAX_HISTORY
    while [ ${#PLOT_DATA[@]} -gt $MAX_HISTORY ]; do
      unset PLOT_DATA[$((PLOT_CURSOR_LAST - MAX_HISTORY))]
    done
  done
}

plot() {
  BC_SCALE="scale=$PLOT_PRECISION+2"

  if [ -z "$NO_LEGEND" ]; then
    # measure legend size
    PLOT_LEGEND_PADDING=2
    PLOT_LEGEND_WIDTH=$((PLOT_WIDTH - PLOT_AXIS_WIDTH - 2 * PLOT_LEGEND_PADDING))
    PLOT_LEGEND_TITLE_WIDTH=8
    declare -a PLOT_LEGEND_TITLE=()
    for SERIES_NAME in "${!PLOT_SERIES[@]}"; do
      SERIES_LENGTH=$(wc -c <<< "$SERIES_NAME" | tr -d ' ')
      if [ $SERIES_LENGTH -gt $PLOT_LEGEND_TITLE_WIDTH ]; then
        PLOT_LEGEND_TITLE_WIDTH=$SERIES_LENGTH
      fi
      PLOT_LEGEND_TITLE+=("$SERIES_NAME")
    done
    if [ $PLOT_LEGEND_TITLE_WIDTH -gt $((PLOT_LEGEND_WIDTH - 4)) ]; then
      # subtract width of ╶╴ line marker and right-padding
      PLOT_LEGEND_TITLE_WIDTH=$((PLOT_LEGEND_WIDTH - 4))
    fi
    PLOT_LEGEND_COLS_N=$((PLOT_LEGEND_WIDTH / (PLOT_LEGEND_TITLE_WIDTH + 4)))
    PLOT_LEGEND_HEIGHT=$((${#PLOT_SERIES[@]} / PLOT_LEGEND_COLS_N))
    if (( ${#PLOT_SERIES[@]} % PLOT_LEGEND_COLS_N > 0 )); then
      PLOT_LEGEND_HEIGHT=$((PLOT_LEGEND_HEIGHT + 1))
    fi

    # change PLOT_HEIGHT to spare legend text
    PLOT_HEIGHT=$((PLOT_HEIGHT - PLOT_LEGEND_HEIGHT))

    # plot legend
    for K in $(seq 0 $(( ${#PLOT_SERIES[@]} - 1))); do
      if (( K % PLOT_LEGEND_COLS_N == 0 )); then
        # new line if not first line of legend
        [ $K -gt 0 ] && echo
        # pad to align with Y axis
        printf "%$((PLOT_AXIS_WIDTH + PLOT_LEGEND_PADDING))s" " "
      fi
      SERIES_NAME="${PLOT_LEGEND_TITLE[$K]}"
      printf "$(put_graph_style $K)╶─╴ $STYLE_LEGEND_LABEL%-${PLOT_LEGEND_TITLE_WIDTH}s " "${SERIES_NAME:0:$PLOT_LEGEND_TITLE_WIDTH}"
    done
    echo
  fi

  PLOT_MIN_Y=${PLOT_MIN_Y:-0}
  PLOT_MAX_Y=${PLOT_MAX_Y:-1}
  PLOT_VSPACING=$(bc <<< "$BC_SCALE; ($PLOT_MAX_Y - $PLOT_MIN_Y) / ($PLOT_HEIGHT - 1)")
  PLOT_AXIS_LABEL_WIDTH=$((PLOT_AXIS_WIDTH - 2))
  PLOT_CURSOR_FIRST=$((PLOT_CURSOR_LAST - (PLOT_WIDTH - PLOT_AXIS_WIDTH) + 1))
  PLOT_CURSOR_FIRST=$((PLOT_CURSOR_FIRST > 1 ? PLOT_CURSOR_FIRST : 1))

  # declare row-based drawing buffer
  declare -A PLOT_GRAPH_DATA

  for K in $(seq $PLOT_CURSOR_FIRST $PLOT_CURSOR_LAST); do

    # map line number N to series name
    declare -A PLOT_GRAPH_LOOKUP

    # calculate data points
    for DATA_POINT in ${PLOT_DATA[$K]}; do
      IFS="=" read SERIES_NAME VALUE <<< "$DATA_POINT"
      N=$(bc <<< "$BC_SCALE; ($VALUE - $PLOT_MIN_Y)/$PLOT_VSPACING")
      N=$(bc <<< "n=$N; (n/1+(n-n/1)*2/1)")
      PLOT_GRAPH_LOOKUP[$((PLOT_HEIGHT - N))]+="
${PLOT_SERIES[$SERIES_NAME]}"
    done

    PLOT_NODE_LIST=""

    # ids of non-continous series in current column
    PLOT_BREAK_NODE_LIST=$(tr -d ' ' <<< "${PLOT_GRAPH_LOOKUP[@]} ${LAST_PLOT_GRAPH_LOOKUP[@]}" | sort | uniq -u)

    # draw column to row memory buffer (PLOT_GRAPH_LOOKUP)
    for N in $(seq $PLOT_HEIGHT); do
      SERIES_IDS="${PLOT_GRAPH_LOOKUP[$N]}"
      if [ -z "${PLOT_GRAPH_DATA[$N]}" ]; then
        # draw ruler (first column)
        if [ -n "$SERIES_IDS" ]; then
          PLOT_GRAPH_DATA[$N]="┼"
        else
          PLOT_GRAPH_DATA[$N]="┤"
        fi
      else
        # draw curve
        LAST_SERIES_IDS="${LAST_PLOT_GRAPH_LOOKUP[$N]}"
        ALL_SERIES_IDS=$(tr -d ' ' <<< "$PLOT_NODE_LIST $SERIES_IDS $LAST_SERIES_IDS" | sort -gr)
        SIGNIFICANT_ID=$(head -n1 <<< "$ALL_SERIES_IDS")

        if [ -n "$SIGNIFICANT_ID" ]; then
          # draw significant
          if ! (grep $SIGNIFICANT_ID >/dev/null <<< "${PLOT_GRAPH_LOOKUP[@]}"); then
            # significant does not close, insert close character
            PLOT_GRAPH_DATA[$N]+="$(put_graph_style $SIGNIFICANT_ID)╴"
          elif ! (grep "$SIGNIFICANT_ID" >/dev/null <<< "${LAST_PLOT_GRAPH_LOOKUP[@]}"); then
            # significant does not open, insert open character
            PLOT_GRAPH_DATA[$N]+="$(put_graph_style $SIGNIFICANT_ID)╶"
          else
            # significant open and close
            if (grep $SIGNIFICANT_ID >/dev/null <<< "$SERIES_IDS"); then
              if (grep $SIGNIFICANT_ID >/dev/null <<< "$LAST_SERIES_IDS"); then
                # use ─ if most significant in both current and last
                PLOT_GRAPH_DATA[$N]+="$(put_graph_style $SIGNIFICANT_ID)─"
              else
                if ! (grep $SIGNIFICANT_ID >/dev/null <<< "$PLOT_NODE_LIST"); then
                  # use ╭ if most significant in current and an open mark
                  PLOT_GRAPH_DATA[$N]+="$(put_graph_style $SIGNIFICANT_ID)╭"
                else
                  # use ╰ if most significant in current and a close mark
                  PLOT_GRAPH_DATA[$N]+="$(put_graph_style $SIGNIFICANT_ID)╰"
                fi
              fi
            else
              if (grep $SIGNIFICANT_ID >/dev/null <<< "$LAST_SERIES_IDS"); then
                if ! (grep $SIGNIFICANT_ID >/dev/null <<< "$PLOT_NODE_LIST"); then
                  # use ╮ if most significant in last and an open mark
                  PLOT_GRAPH_DATA[$N]+="$(put_graph_style $SIGNIFICANT_ID)╮"
                else
                  # use ╯ if most significant in last and a close mark
                  PLOT_GRAPH_DATA[$N]+="$(put_graph_style $SIGNIFICANT_ID)╯"
                fi
              else
                # use │ if less significant
                PLOT_GRAPH_DATA[$N]+="$(put_graph_style $SIGNIFICANT_ID)│"
              fi
            fi
          fi

          # update active series ids except series in PLOT_BREAK_NODE_LIST
          ALL_SERIES_IDS=$(tr -d ' ' <<< "$ALL_SERIES_IDS $PLOT_BREAK_NODE_LIST $PLOT_BREAK_NODE_LIST" | sort | uniq -u)
          PLOT_NODE_LIST=$(uniq -u <<< "$ALL_SERIES_IDS")
        else
          # draw blank
          PLOT_GRAPH_DATA[$N]+=" "
        fi
      fi
    done

    # copy PLOT_GRAPH_LOOKUP to LAST_PLOT_GRAPH_LOOKUP for later use.
    unset LAST_PLOT_GRAPH_LOOKUP
    declare -A LAST_PLOT_GRAPH_LOOKUP
    for KEY in "${!PLOT_GRAPH_LOOKUP[@]}"; do
      LAST_PLOT_GRAPH_LOOKUP[$KEY]=${PLOT_GRAPH_LOOKUP[$KEY]}
    done
    unset PLOT_GRAPH_LOOKUP

  done

  # print rows
  for N in $(seq $PLOT_HEIGHT); do
    PLOT_LINE_Y=$(bc <<< "$BC_SCALE; $PLOT_MAX_Y - $PLOT_VSPACING * ($N - 1)")
    printf "${STYLE_AXIS_LABEL}%${PLOT_AXIS_LABEL_WIDTH}.2f${STYLE_AXIS_RULER} ${PLOT_GRAPH_DATA[$N]}\n" $PLOT_LINE_Y
  done

  unset PLOT_GRAPH_DATA
}

if [ "$(basename $0)" == "chart.sh" ]; then
  to_chart
fi
