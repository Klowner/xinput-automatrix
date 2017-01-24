#!/bin/sh
#
# Automatically calculate and set xinput coordinate transformation matrix
# for all matching devices listed in DEVICES array
#
# usage:
#  ./xinput-automatrix.sh
#
# Mark Riedesel <mark@klowner.com>
#
# DEVICES array contains an xinput device name to search
# for and an EDID manufacturer and product which is identified
# by 4 hex bytes.
#
# To add a new device, you can list displays with xrandr --props
# and then extract the first 8 characters of the EDID after
# 00ffffffffffff00

DEVICES=(
	"Bosto Kingtee 22HD Pen:2a590027"
)

get_display_device() {
	local search_edid=${1}

	local old_IFS=$IFS
	IFS=$'\n'

	local COUNT=0
	local MODE='display'
	local DISPLAY_ID=''
	local EDID=''

	while read LINE; do
		case $MODE in
			'display')
				if [[ "$LINE" =~ ^([A-Z])*-[A-Z0-9]?-?[0-9]*[[:space:]]connected ]]; then
					MODE='edid-header'
					DISPLAY_ID=${LINE%% *}
				fi
				;;
			'edid-header')
				if [[ "$LINE" =~ ^[[:blank:]]*EDID ]]; then
					MODE='edid'
				fi
				;;
			'edid')
				if [[ "$LINE" =~ ^[[:blank:]]*00ffffffffffff00([0-9a-f]*) ]]; then
					MODE='display'
					LINE=${LINE#"${LINE%%[![:space:]]*}"}
					EDID="${LINE:16:8}"
					if [[ $EDID == $search_edid ]]; then
						DISPLAY_FOUND="$DISPLAY_ID"
					fi
				fi
				;;
		esac

		if [[ "$DISPLAY_FOUND" != '' ]]; then
			break;
		fi
	done <<< "$(xrandr --props)"

	IFS=$old_IFS

	if [ "$DISPLAY_FOUND" != '' ]; then
		DISPLAY_DEVICE=$DISPLAY_ID
		return 0
	fi

	return 1
}

get_current_dimensions() {
	local DIM=($(xrandr | head -1 | sed -n 's/.*current \([0-9]*\) x \([0-9]*\).*/\1 \2/p'))
	TOTAL_WIDTH=${DIM[0]}
	TOTAL_HEIGHT=${DIM[1]}
}

get_tablet_dimensions() {
	local target_display=${1}
	local dims=()
	local ids=()

	for x in $(xrandr --listactivemonitors | tail -n +2 | awk '{print $3 ";" $4}'); do
		VALS=(${x//;/ })
		dims+=(${VALS[0]})
		ids+=(${VALS[1]})
	done

	if [[ -z $target_display ]]; then
		echo "Please specify which display to use: ${ids[@]}"
		exit 0
	fi

	local match_index=-1
	for ((i = 0; i < ${#dims[@]}; i++)) do
		if [[ ${ids[$i]} == *"${target_display}"* ]]; then
			match_index=$i
			break
		fi
	done

	if [[ $match_index -lt 0 ]]; then
		echo "Specified display device not found: $target_display"
		exit 1
	fi

	local parsed_dims=($(echo ${dims[$match_index]} | sed -n 's/\([0-9]*\)\/[0-9]*x\([0-9]*\)\/[0-9]*+\([0-9]*\)+\([0-9]*\)/\1 \2 \3 \4/p'))
	SCREEN_WIDTH=${parsed_dims[0]}
	SCREEN_HEIGHT=${parsed_dims[1]}
	SCREEN_OFFSET_X=${parsed_dims[2]}
	SCREEN_OFFSET_Y=${parsed_dims[3]}
}

calculate_matrix() {
	local c=()
	for x in "$SCREEN_WIDTH/$TOTAL_WIDTH" "$SCREEN_OFFSET_X/$TOTAL_WIDTH" \
			"$SCREEN_HEIGHT/$TOTAL_HEIGHT" "$SCREEN_OFFSET_Y/$TOTAL_HEIGHT"; do
		c+=($(echo "scale=8; $x" | bc))
	done

	TRANSFORMATION_MATRIX="${c[0]} 0 ${c[1]} 0 ${c[2]} ${c[3]} 0 0 1"
}

set_matrix() {
	local device="$1"
	if [[ -z $device ]]; then
		echo "Specified xinput device not found"
		exit 1
	fi
	$(xinput set-prop "$device" 'Coordinate Transformation Matrix' $TRANSFORMATION_MATRIX)
}

identify_xinput_devices() {
	# GET LIST OF INPUT DEVICES VIA XINPUT
	local seen=()
	local old_IFS=$IFS
	IFS=$'\n'
	for x in $(xinput list --name-only); do
		seen+=($x)
	done
	IFS=$old_IFS

	# ITERATE THROUGH ALL KNOWN DEVICES
	for x in "${DEVICES[@]}"; do
		local xinput_dev=${x%%:*}
		local edid=${x##*:}

		for seen in "${seen[@]}"; do
			if [[ "$seen" == *"$xinput_dev"* ]]; then
				if get_display_device $edid; then
					get_current_dimensions "$DISPLAY_DEVICE"
					get_tablet_dimensions "$DISPLAY_DEVICE"
					calculate_matrix
					set_matrix "$seen"
					echo $seen on $DISPLAY_DEVICE
				fi
				break
			fi
		done
	done
	return 0
}

identify_xinput_devices
exit $?
