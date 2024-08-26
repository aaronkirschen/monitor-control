#!/bin/bash

# monitor-config - Configure multiple monitors with kscreen-doctor
#
# This script allows saving and restoring multi-monitor layouts, disabling
# specific monitors. Monitor positions and priorities are persisted in a config file.
#
# Usage: monitor-config [OPTIONS] [MONITOR]...
#
# Options:
#   -h, --help             Print help and exit
#   -s, --save             Save current layout to config file
#   -l, --list             List current monitors
#   -L, --left             Enable only leftmost monitor
#   -R, --right            Enable only rightmost monitor
#   -LR, --left-right      Enable only leftmost and rightmost monitors
#
# The monitors passed as positional arguments will be disabled.
# With no monitor arguments, the layout from the config file is applied.

CONFIG_FILE=~/.config/monitor_config
CONFIG_SAVED=false

POSITIONAL_ARGS=()

HELP=false
SAVE=false
LIST=false
LEFT_ONLY=false
RIGHT_ONLY=false
LEFT_RIGHT_ONLY=false

print_help() {
  echo '''
Configure monitors with kscreen-doctor. This script allows saving and restoring multi-monitor layouts, disabling
specific monitors, and enabling only the left or right monitor. Monitor
positions and priorities are persisted in a config file.
 '''
  echo "Usage: $(basename $0) [OPTIONS] [MONITOR]..."
  echo ""
  echo "Options:"
  echo "  -h, --help             Print this help"
  echo "  -s, --save             Save current layout to config file"
  echo "  -l, --list             List current monitors"
  echo "  -L, --left             Enable only leftmost monitor"
  echo "  -R, --right            Enable only rightmost monitor"
  echo "  -LR, --left-right      Enable only leftmost and rightmost monitors"
  echo ""
  echo "The monitors passed as arguments will be disabled."
  echo "With no arguments, the layout from the config file is applied."
}

while [[ $# -gt 0 ]]; do
    case $1 in
    -h|--help)
      HELP=true
      shift
      ;;
    -s|--save)
        SAVE=true
        shift
        ;;
    -l | --list)
        LIST=true
        shift
        ;;
    -L | --left)
        LEFT_ONLY=true
        shift
        ;;
    -R | --right)
        RIGHT_ONLY=true
        shift
        ;;
    -LR | --left-right)
        LEFT_RIGHT_ONLY=true
        shift
        ;;
    *)
        POSITIONAL_ARGS+=("$1")
        shift
        ;;
    esac
done


if $HELP; then
  print_help
  exit 0
fi

# List monitors
if $LIST; then
    echo "Monitors:"
    kscreen-doctor -o | grep 'Output: ' | awk '{print $3}'
    exit 0
fi

set -- "${POSITIONAL_ARGS[@]}"

if [ -f $CONFIG_FILE ] && grep -q "." $CONFIG_FILE; then
  CONFIG_SAVED=true
elif $SAVE; then
  touch $CONFIG_FILE
  CONFIG_SAVED=true
else
    echo "Error: Monitor config has not been saved yet. Please run with --save first."
    exit 1
fi

# Get monitor info
INFO=$(kscreen-doctor -o | tr -d '\n' | sed -e 's/Output:/\n&/g')
# Populate config map
declare -A POSITIONS PRIORITIES RESOLUTIONS
while IFS= read -r LINE; do
    MONITOR_NAME=$(echo "$LINE" | awk -F' ' '{print $3}')
    POSITION=$(echo "$LINE" | awk -F' ' '{for (i=1; i<=NF; i++) if ($i ~ /Geometry:/) print $(i+1)}')
    POSITIONS[$MONITOR_NAME]=$POSITION
    PRIORITY=$(echo "$LINE" | awk -F' ' '{for (i=1; i<=NF; i++) if ($i ~ /priority/) print $(i+1)}')
    PRIORITIES[$MONITOR_NAME]=$PRIORITY
    RESOLUTION=$(echo "$LINE" | awk -F' ' '{for (i=1; i<=NF; i++) if ($i ~ /Geometry:/) print $(i+2)}' | tr -d '()')
    RESOLUTIONS[$MONITOR_NAME]=$RESOLUTION
done < <(echo "$INFO" | grep 'Output:')


if $SAVE; then
    # Save current positions and priorities
    for MONITOR in $(echo "$INFO" | grep 'Output: ' | awk '{print $3}'); do
        POS=${POSITIONS[$MONITOR]}
        PRIORITY=${PRIORITIES[$MONITOR]}
        if grep -q "$MONITOR" $CONFIG_FILE; then
            sed -i "/^$MONITOR/c$MONITOR $POS $PRIORITY" $CONFIG_FILE
        else
            echo "$MONITOR $POS $PRIORITY" >> $CONFIG_FILE
        fi
    done

    echo "Monitor configuration saved to $CONFIG_FILE:"
    cat $CONFIG_FILE
    CONFIG_SAVED=true
    exit
fi

# Get leftmost and rightmost monitors
if $LEFT_ONLY; then
    LEFT_MONITOR=$(for m in "${!POSITIONS[@]}"; do
        LEFT_X=$(echo ${POSITIONS[$m]} | awk -F',' '{print $1}')
        echo $LEFT_X $m
    done | sort -n | head -n1 | awk '{print $2}')

    echo "Enabling only $LEFT_MONITOR"

    CMD="kscreen-doctor output.$LEFT_MONITOR.enable output.$LEFT_MONITOR.position.0,0"

    # Disable all other monitors
    for MONITOR in "${!POSITIONS[@]}"; do
        if [ "$MONITOR" != "$LEFT_MONITOR" ]; then
            CMD="$CMD output.$MONITOR.disable"
        fi
    done

elif $RIGHT_ONLY; then
    RIGHT_MONITOR=$(for m in "${!POSITIONS[@]}"; do
        RIGHT_X=$(echo ${POSITIONS[$m]} | awk -F',' '{print $1}')
        echo $RIGHT_X $m
    done | sort -nr | head -n1 | awk '{print $2}')

    echo "Enabling only $RIGHT_MONITOR"

    CMD="kscreen-doctor output.$RIGHT_MONITOR.enable output.$RIGHT_MONITOR.position.0,0"

    # Disable all other monitors
    for MONITOR in "${!POSITIONS[@]}"; do
        if [ "$MONITOR" != "$RIGHT_MONITOR" ]; then
            CMD="$CMD output.$MONITOR.disable"
        fi
    done

elif $LEFT_RIGHT_ONLY; then
    LEFT_MONITOR=$(for m in "${!POSITIONS[@]}"; do
        LEFT_X=$(echo ${POSITIONS[$m]} | awk -F',' '{print $1}')
        echo $LEFT_X $m
    done | sort -n | head -n1 | awk '{print $2}')

    RIGHT_MONITOR=$(for m in "${!POSITIONS[@]}"; do
        RIGHT_X=$(echo ${POSITIONS[$m]} | awk -F',' '{print $1}')
        echo $RIGHT_X $m
    done | sort -nr | head -n1 | awk '{print $2}')

    echo "Enabling only $LEFT_MONITOR and $RIGHT_MONITOR"

    # Calculate new position for the right monitor to be directly adjacent to the left monitor
    LEFT_WIDTH=$(echo "${RESOLUTIONS[$LEFT_MONITOR]}" | awk -Fx '{print $1}')
    NEW_RIGHT_POS="$LEFT_WIDTH,0"

    CMD="kscreen-doctor output.$LEFT_MONITOR.enable output.$LEFT_MONITOR.position.0,0 "
    CMD="$CMD output.$RIGHT_MONITOR.enable output.$RIGHT_MONITOR.position.$NEW_RIGHT_POS"

    # Disable all other monitors
    for MONITOR in "${!POSITIONS[@]}"; do
        if [ "$MONITOR" != "$LEFT_MONITOR" ] && [ "$MONITOR" != "$RIGHT_MONITOR" ]; then
            CMD="$CMD output.$MONITOR.disable"
        fi
    done

else
    # Build command based on saved config
    CMD="kscreen-doctor"
    for MONITOR in "${!POSITIONS[@]}"; do
        if [[ " $DISABLE_MONITORS " =~ " $MONITOR " ]]; then
            CMD="$CMD output.$MONITOR.disable"
        else
            POS=$(grep "$MONITOR" $CONFIG_FILE | awk '{print $2}')
            PRIORITY=$(grep "$MONITOR" $CONFIG_FILE | awk '{print $3}')

            if [ -z "$POS" ]; then
                POS=${POSITIONS[$MONITOR]}
                PRIORITY=${PRIORITIES[$MONITOR]}
            fi
            CMD="$CMD output.$MONITOR.enable output.$MONITOR.position.$POS output.$MONITOR.priority.$PRIORITY"
        fi
    done
fi

# Execute command
CMD="$(echo "$CMD" | sed 's/\x1b\[[0-9;]*[a-zA-Z]//g')" # Clean command
$CMD
exit 0
