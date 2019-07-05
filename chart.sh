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
  FLOAT_PRECISION=${FLOAT_PRECISION:-2}

  PLOT_AXIS_WIDTH=${AXIS_WIDTH:-12}
  PLOT_FLOAT_PRECISION=$((FLOAT_PRECISION + 2))
  PLOT_FLOAT_1=1$(printf "%0${PLOT_FLOAT_PRECISION}d" 0)

  # setup series data store
  declare -A PLOT_SERIES
  declare -A PLOT_DATA
  PLOT_CURSOR_LAST=0
  repl
}

repl() {
  while read COMMAND PAYLOAD; do
    case $COMMAND in
      a|append)
        # add to existing series data
        PLOT_CURSOR_LAST=$((PLOT_CURSOR_LAST + 1))
        ;;
      u|update)
        # change latest series data
        unset PLOT_DATA[$PLOT_CURSOR_LAST]
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

        if [ "$MIN_Y" != "auto" -o "$MAX_Y" == "auto" ]; then
          MIN_MAX=$(tr -s ' ' '\n' <<< ${PLOT_DATA[@]} | cut -d'=' -f2 | sort -n | sed -n '1p;$p')
          MIN_MAX=${MIN_MAX//$'\n'/ }
          read PLOT_MIN_Y PLOT_MAX_Y <<< "$MIN_MAX"
        fi
        if [ "$MIN_Y" != "auto" ]; then
          PLOT_MIN_Y=$MIN_Y
          PLOT_MIN_Y=$(printf "%.${PLOT_FLOAT_PRECISION}f" $PLOT_MIN_Y)
          PLOT_MIN_Y=${PLOT_MIN_Y//./}
          PLOT_MIN_Y=$((10#$PLOT_MIN_Y))
        fi
        if [ "$MAX_Y" != "auto" ]; then
          PLOT_MAX_Y=$MAX_Y
          PLOT_MAX_Y=$(printf "%.${PLOT_FLOAT_PRECISION}f" $PLOT_MAX_Y)
          PLOT_MAX_Y=${PLOT_MAX_Y//./}
          PLOT_MAX_Y=$((10#$PLOT_MAX_Y))
        fi
        if (( PLOT_MAX_Y <= PLOT_MIN_Y )); then
          if [ "$MAX_Y" != "auto" ]; then
            PLOT_MIN_Y=$((PLOT_MAX_Y - PLOT_FLOAT_1))
          else
            PLOT_MAX_Y=$((PLOT_MIN_Y + PLOT_FLOAT_1))
          fi
        fi

        OUTPUT_BUFFER=$(plot)
        cat <<< "$OUTPUT_BUFFER$(tput sgr0)"
        unset OUTPUT_BUFFER
        continue
        ;;
      .|source)
        repl < "$PAYLOAD"
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

    for SERIES_POINT in $PAYLOAD; do
      IFS='=' read SERIES_NAME VALUE <<< "$SERIES_POINT"
      if [ -z "${PLOT_SERIES[$SERIES_NAME]}" ]; then
        # add series name to PLOT_SERIES
        PLOT_SERIES[$SERIES_NAME]=${#PLOT_SERIES[@]}
      fi
      # scale float to integer
      VALUE=$(printf "%.${PLOT_FLOAT_PRECISION}f" $VALUE)
      VALUE=${VALUE//./}
      VALUE=$((10#$VALUE))
      PLOT_DATA[$PLOT_CURSOR_LAST]+="$SERIES_NAME=$VALUE "
    done

    # trim history to MAX_HISTORY
    while [ ${#PLOT_DATA[@]} -gt $MAX_HISTORY ]; do
      unset PLOT_DATA[$((PLOT_CURSOR_LAST - MAX_HISTORY))]
    done
  done
}

plot() {
  if [ -z "$NO_LEGEND" ]; then
    # measure legend size
    PLOT_LEGEND_PADDING=2
    PLOT_LEGEND_WIDTH=$((PLOT_WIDTH - PLOT_AXIS_WIDTH - 2 * PLOT_LEGEND_PADDING))
    PLOT_LEGEND_TITLE_WIDTH=8
    declare -a PLOT_LEGEND_TITLE=()
    while read SERIES_NAME; do
      SERIES_LENGTH=$(wc -c <<< "$SERIES_NAME" | tr -d ' ')
      if [ $SERIES_LENGTH -gt $PLOT_LEGEND_TITLE_WIDTH ]; then
        PLOT_LEGEND_TITLE_WIDTH=$SERIES_LENGTH
      fi
      PLOT_LEGEND_TITLE+=("$SERIES_NAME")
    done < <(tr -s ' ' '\n' <<< "${!PLOT_SERIES[@]}" | sort)
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
      printf "$(put_graph_style ${PLOT_SERIES[$SERIES_NAME]})╶─╴ $STYLE_LEGEND_LABEL%-${PLOT_LEGEND_TITLE_WIDTH}s " "${SERIES_NAME:0:$PLOT_LEGEND_TITLE_WIDTH}"
    done
    echo
  fi

  PLOT_MIN_Y=${PLOT_MIN_Y:-0}
  PLOT_MAX_Y=${PLOT_MAX_Y:-1}
  PLOT_VSPACING=$(((PLOT_MAX_Y - PLOT_MIN_Y) / (PLOT_HEIGHT - 1)))
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
      N=$(((VALUE - PLOT_MIN_Y) / PLOT_VSPACING))
      R=$(((VALUE - PLOT_MIN_Y) % PLOT_VSPACING))
      if (( R * 2 >= PLOT_VSPACING )); then
        N=$((N + 1))
      fi
      PLOT_GRAPH_LOOKUP[$((PLOT_HEIGHT - N))]+=" ${PLOT_SERIES[$SERIES_NAME]} "
    done

    PLOT_NODE_LIST=""

    # ids of non-continous series in current column
    PLOT_BREAK_NODE_LIST="${PLOT_GRAPH_LOOKUP[@]} ${LAST_PLOT_GRAPH_LOOKUP[@]}"
    PLOT_BREAK_NODE_LIST="$(sort <<< "${PLOT_BREAK_NODE_LIST// /$'\n'}" | uniq -u)"
    PLOT_BREAK_NODE_LIST="${PLOT_BREAK_NODE_LIST//$'\n'/ }"

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

        # use a default value
        read SIGNIFICANT_ID _ <<< "$PLOT_NODE_LIST $SERIES_IDS $LAST_SERIES_IDS"

        # use largest sequence id as significant
        for SERIES_ID in $PLOT_NODE_LIST $SERIES_IDS $LAST_SERIES_IDS; do
          if ((SERIES_ID > SIGNIFICANT_ID)); then
            SIGNIFICANT_ID=$SERIES_ID
          fi
        done

        if [ -n "$SIGNIFICANT_ID" ]; then
          # draw significant
          if [[ ! " ${PLOT_GRAPH_LOOKUP[@]} " =~ " $SIGNIFICANT_ID " ]]; then
            # significant does not close, insert close character
            PLOT_GRAPH_DATA[$N]+="$(put_graph_style $SIGNIFICANT_ID)╴"
          elif [[ ! " ${LAST_PLOT_GRAPH_LOOKUP[@]} " =~ " $SIGNIFICANT_ID " ]]; then
            # significant does not open, insert open character
            PLOT_GRAPH_DATA[$N]+="$(put_graph_style $SIGNIFICANT_ID)╶"
          else
            # significant open and close
            if [[ " $SERIES_IDS " =~ " $SIGNIFICANT_ID " ]]; then
              if [[ " $LAST_SERIES_IDS " =~ " $SIGNIFICANT_ID " ]]; then
                # use ─ if most significant in both current and last
                PLOT_GRAPH_DATA[$N]+="$(put_graph_style $SIGNIFICANT_ID)─"
              else
                if [[ ! " $PLOT_NODE_LIST " =~ " $SIGNIFICANT_ID " ]]; then
                  # use ╭ if most significant in current and an open mark
                  PLOT_GRAPH_DATA[$N]+="$(put_graph_style $SIGNIFICANT_ID)╭"
                else
                  # use ╰ if most significant in current and a close mark
                  PLOT_GRAPH_DATA[$N]+="$(put_graph_style $SIGNIFICANT_ID)╰"
                fi
              fi
            else
              if [[ " $LAST_SERIES_IDS " =~ " $SIGNIFICANT_ID " ]]; then
                if [[ ! " $PLOT_NODE_LIST " =~ " $SIGNIFICANT_ID " ]]; then
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
          PLOT_NODE_LIST="$PLOT_NODE_LIST $SERIES_IDS $LAST_SERIES_IDS $PLOT_BREAK_NODE_LIST $PLOT_BREAK_NODE_LIST"
          PLOT_NODE_LIST="$(sort <<< "${PLOT_NODE_LIST// /$'\n'}" | uniq -u)"
          PLOT_NODE_LIST="${PLOT_NODE_LIST//$'\n'/ }"
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
    PLOT_LINE_Y=$(printf "%0${PLOT_FLOAT_PRECISION}d" $((PLOT_MAX_Y - PLOT_VSPACING * (N - 1))))
    PLOT_LINE_Y="${PLOT_LINE_Y::-$PLOT_FLOAT_PRECISION}.${PLOT_LINE_Y:(-$PLOT_FLOAT_PRECISION)}"
    printf "${STYLE_AXIS_LABEL}%${PLOT_AXIS_LABEL_WIDTH}.${FLOAT_PRECISION}f${STYLE_AXIS_RULER} ${PLOT_GRAPH_DATA[$N]}\n" $PLOT_LINE_Y
  done

  unset PLOT_GRAPH_DATA
}

if [ "$(basename $0)" == "chart.sh" ]; then
  to_chart
fi
