#!/bin/bash

TERM_BG=${TERM_BG:-dark}

################
# Chart Styles #
################

STYLE_AXIS_RULER=$(tput sgr0)
STYLE_AXIS_LABEL=$(tput sgr0)
STYLE_LEGEND_LABEL=$(tput sgr0)

if [ -z "$COLOR_SCHEME" ]; then
  if [ $TERM_BG == "light" ]; then
    if [ $(tput colors) -ge 256 2>/dev/null ]; then
      declare -a COLOR_SCHEME=(124 34 220 20 92 23)
    else
      # use 4-bit light color scheme
      declare -a COLOR_SCHEME=(1 2 3 4 5 6)
    fi
  else
    if [ $(tput colors) -ge 256 2>/dev/null ]; then
      # use 8-bit dark color scheme
      declare -a COLOR_SCHEME=(205 121 208 81 226 69 191 204 210 219)
    else
      # use 4-bit dark color scheme
      declare -a COLOR_SCHEME=(1 2 3 4 5 6 7)
    fi
  fi
fi

COLOR_SCHEME_SIZE=${#COLOR_SCHEME[@]}
put_graph_style() {
  tput sgr0
  if [ "$(($1 / $COLOR_SCHEME_SIZE % 2))" == "1" ]; then
    tput bold
  fi
  tput setaf ${COLOR_SCHEME[$(($1 % $COLOR_SCHEME_SIZE))]}
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
        fi
        if [ "$HEIGHT" == "auto" ]; then
          PLOT_HEIGHT=$(($(tput lines) - 1))
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
      if [ -z "${PLOT_GRAPH_LOOKUP[$((PLOT_HEIGHT - N))]}" ]; then
        PLOT_GRAPH_LOOKUP[$((PLOT_HEIGHT - N))]="${PLOT_SERIES[$SERIES_NAME]}"
      else
        PLOT_GRAPH_LOOKUP[$((PLOT_HEIGHT - N))]="${PLOT_GRAPH_LOOKUP[$((PLOT_HEIGHT - N))]}
${PLOT_SERIES[$SERIES_NAME]}"
      fi
    done

    PLOT_NODE_LIST=""

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
        ALL_SERIES_IDS=$(sort -gr <<< "$PLOT_NODE_LIST
$SERIES_IDS
$LAST_SERIES_IDS")
        SIGNIFICANT_ID=$(head -n1 <<< "$ALL_SERIES_IDS")
        if [ -n "$SIGNIFICANT_ID" ]; then
          if ! (grep $SIGNIFICANT_ID >/dev/null <<< "${PLOT_GRAPH_LOOKUP[@]}"); then
            # significant does not close, insert close character
            PLOT_GRAPH_DATA[$N]="${PLOT_GRAPH_DATA[$N]}$(put_graph_style $SIGNIFICANT_ID)╴"
            while [ -n "$SIGNIFICANT_ID" ] && ! (grep $SIGNIFICANT_ID >/dev/null <<< "${PLOT_GRAPH_LOOKUP[@]}"); do
              ALL_SERIES_IDS=$(tail -n+2 <<< "$ALL_SERIES_IDS")
              SIGNIFICANT_ID=$(head -n1 <<< "$ALL_SERIES_IDS")
            done
          elif ! (grep "$SIGNIFICANT_ID" >/dev/null <<< "${LAST_PLOT_GRAPH_LOOKUP[@]}"); then
            # significant does not open, insert open character
            PLOT_GRAPH_DATA[$N]="${PLOT_GRAPH_DATA[$N]}$(put_graph_style $SIGNIFICANT_ID)╶"
            while [ -n "$SIGNIFICANT_ID" ] && ! (grep "$SIGNIFICANT_ID" >/dev/null <<< "${LAST_PLOT_GRAPH_LOOKUP[@]}"); do
              ALL_SERIES_IDS=$(tail -n+2 <<< "$ALL_SERIES_IDS")
              SIGNIFICANT_ID=$(head -n1 <<< "$ALL_SERIES_IDS")
            done
          else
            # significant open and close
            if (grep $SIGNIFICANT_ID >/dev/null <<< "$SERIES_IDS"); then
              if (grep $SIGNIFICANT_ID >/dev/null <<< "$LAST_SERIES_IDS"); then
                # use ─ if most significant in both current and last
                PLOT_GRAPH_DATA[$N]="${PLOT_GRAPH_DATA[$N]}$(put_graph_style $SIGNIFICANT_ID)─"
              else
                if ! (grep $SIGNIFICANT_ID >/dev/null <<< "$PLOT_NODE_LIST"); then
                  # use ╭ if most significant in current and an open mark
                  PLOT_GRAPH_DATA[$N]="${PLOT_GRAPH_DATA[$N]}$(put_graph_style $SIGNIFICANT_ID)╭"
                else
                  # use ╰ if most significant in current and a close mark
                  PLOT_GRAPH_DATA[$N]="${PLOT_GRAPH_DATA[$N]}$(put_graph_style $SIGNIFICANT_ID)╰"
                fi
              fi
            else
              if (grep $SIGNIFICANT_ID >/dev/null <<< "$LAST_SERIES_IDS"); then
                if ! (grep $SIGNIFICANT_ID >/dev/null <<< "$PLOT_NODE_LIST"); then
                  # use ╮ if most significant in last and an open mark
                  PLOT_GRAPH_DATA[$N]="${PLOT_GRAPH_DATA[$N]}$(put_graph_style $SIGNIFICANT_ID)╮"
                else
                  # use ╯ if most significant in last and a close mark
                  PLOT_GRAPH_DATA[$N]="${PLOT_GRAPH_DATA[$N]}$(put_graph_style $SIGNIFICANT_ID)╯"
                fi
              else
                # use │ if less significant
                PLOT_GRAPH_DATA[$N]="${PLOT_GRAPH_DATA[$N]}$(put_graph_style $SIGNIFICANT_ID)│"
              fi
            fi
          fi
          PLOT_NODE_LIST=$(uniq -u <<< "$ALL_SERIES_IDS")
        else
          # draw blank
          PLOT_GRAPH_DATA[$N]="${PLOT_GRAPH_DATA[$N]} "
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

to_chart
