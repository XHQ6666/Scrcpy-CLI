#!/usr/bin/env bash

CONFIG_FILE="$HOME/scrcpy_config.json"
selected_profile=""
dsp_args_str=""
cam_args_str=""

dsp_args_array=()
cam_args_array=()
devices=()
statuses=()
selected=""
selected_status=""

action_pause() {
    read -r -p "Press Enter to continue..." _
}

check_deps() {
    local missing=0
    for cmd in adb scrcpy python3; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            echo "Command not found: $cmd"
            missing=1
        fi
    done

    if [ "$missing" -ne 0 ]; then
        echo
        echo "Please install the required dependencies first. Common distro examples:"
        echo "  Debian/Ubuntu: sudo apt install adb scrcpy python3"
        echo "  Fedora:        sudo dnf install android-tools scrcpy python3"
        echo "  Arch Linux:    sudo pacman -S android-tools scrcpy python"
        echo
        echo "Note: the commands above use sudo and modify your system packages. Verify the package sources first."
        echo
        action_pause
        exit 1
    fi
}

split_args_to_array() {
    local input="$1"
    local target="$2"
    local items=()
    local line

    while IFS= read -r line; do
        items+=("$line")
    done < <(python3 - "$input" <<'PY'
import shlex, sys
s = sys.argv[1]
if s.strip():
    for item in shlex.split(s):
        print(item)
PY
)

    eval "$target=()"
    for line in "${items[@]}"; do
        printf -v __q '%q' "$line"
        eval "$target+=( $__q )"
    done
}

load_config() {
    local result
    result="$(python3 - "$CONFIG_FILE" <<'PY'
import json, os, sys
p = sys.argv[1]
if not os.path.exists(p):
    print("\t\t")
    raise SystemExit
try:
    with open(p, 'r', encoding='utf-8') as f:
        c = json.load(f)
except Exception:
    print("\t\t")
    raise SystemExit

s = c.get('selected', '') if isinstance(c, dict) else ''
d = ''
cam = ''
pr = None
if s and isinstance(c, dict):
    profiles = c.get('profiles')
    if isinstance(profiles, dict) and s in profiles:
        pr = profiles.get(s)
    elif s in c:
        pr = c.get(s)

if isinstance(pr, dict):
    d = pr.get('display_mirror', '') or ''
    cam = pr.get('camera_mirror', '') or ''

print(f"{str(s).replace(chr(9), ' ')}\t{str(d).replace(chr(9), ' ')}\t{str(cam).replace(chr(9), ' ')}")
PY
)"

    selected_profile="${result%%$'\t'*}"
    local rest="${result#*$'\t'}"
    if [ "$rest" = "$result" ]; then
        dsp_args_str=""
        cam_args_str=""
    else
        dsp_args_str="${rest%%$'\t'*}"
        cam_args_str="${rest#*$'\t'}"
        if [ "$cam_args_str" = "$rest" ]; then
            cam_args_str=""
        fi
    fi

    split_args_to_array "$dsp_args_str" dsp_args_array
    split_args_to_array "$cam_args_str" cam_args_array
}

list_profiles() {
    python3 - "$CONFIG_FILE" <<'PY'
import json, os, sys
p = sys.argv[1]
if not os.path.exists(p):
    raise SystemExit
try:
    with open(p, 'r', encoding='utf-8') as f:
        c = json.load(f)
except Exception:
    raise SystemExit
if not isinstance(c, dict):
    raise SystemExit
profiles = c.get('profiles')
if isinstance(profiles, dict):
    for name in profiles.keys():
        print(name)
else:
    for name in c.keys():
        if name != 'selected':
            print(name)
PY
}

save_selected_profile() {
    local profile="$1"
    python3 - "$CONFIG_FILE" "$profile" <<'PY'
import json, os, sys
p = sys.argv[1]
selected = sys.argv[2]
if not os.path.exists(p):
    raise SystemExit(1)
with open(p, 'r', encoding='utf-8') as f:
    c = json.load(f)
if not isinstance(c, dict):
    raise SystemExit(1)
c['selected'] = selected
with open(p, 'w', encoding='utf-8') as f:
    json.dump(c, f, ensure_ascii=False, indent=2)
    f.write('\n')
PY
}

choose_device() {
    devices=()
    statuses=()
    local serial status

    while IFS=$'\t' read -r serial status; do
        [ -z "$serial" ] && continue
        devices+=("$serial")
        statuses+=("$status")
    done < <(adb devices | awk 'NR>1 && $1 != "" {print $1 "\t" $2}')

    local count="${#devices[@]}"
    if [ "$count" -eq 0 ]; then
        echo "No connected devices detected."
        action_pause
        return 1
    fi

    if [ "$count" -eq 1 ]; then
        selected="${devices[0]}"
        selected_status="${statuses[0]}"
        echo "Detected one device: $selected status: $selected_status"
        echo "Connecting..."
        sleep 2
    else
        echo "Detected ${count} devices. Please select one:"
        local i label choice
        for ((i=0; i<count; i++)); do
            label="[${statuses[$i]}]"
            case "${statuses[$i]}" in
                device) label="[online]" ;;
                unauthorized) label="[unauthorized]" ;;
                offline) label="[offline]" ;;
            esac
            echo "$((i + 1)). ${devices[$i]} $label"
        done

        echo
        read -r -p "Enter device number: " choice
        if ! [[ "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 1 ] || [ "$choice" -gt "$count" ]; then
            echo "Invalid input, returning to main menu."
            action_pause
            return 1
        fi

        selected="${devices[$((choice - 1))]}"
        selected_status="${statuses[$((choice - 1))]}"
    fi

    if [ "$selected_status" = "offline" ]; then
        echo "Device is offline. Attempting to reconnect..."
        adb disconnect "$selected"
        adb connect "$selected"
        echo "Reconnect attempted. Please check whether the device is online."
        action_pause
        return 1
    fi

    return 0
}

display_mirror() {
    clear
    echo "[Screen Mirroring]"
    scrcpy -s "$selected" "${dsp_args_array[@]}"
}

cam_mirror() {
    clear
    echo "[Camera Mirroring]"
    echo

    local cam cam_direction
    read -r -p "Select camera ID (enter b to return): " cam
    [ "$cam" = "b" ] && return 0

    if [ "$cam" = "1" ]; then
        cam_direction="flip90"
    else
        cam_direction="90"
    fi

    scrcpy -s "$selected" --video-source=camera --camera-id="$cam" "${cam_args_array[@]}" --display-orientation="$cam_direction"
}

mic_audio() {
    clear
    echo "[Microphone Audio]"
    scrcpy -s "$selected" --audio-source=mic --no-video
}

call_audio() {
    clear
    echo "[Call Audio]"
    echo
    echo "1. Both Sides Audio"
    echo "2. Local Audio"
    echo "3. Remote Audio"
    echo

    local choice audio_source
    read -r -p "Enter option number (Enter for both sides audio, b to return): " choice
    case "$choice" in
        ""|1)
            audio_source="voice-call"
            ;;
        2)
            audio_source="voice-call-downlink"
            ;;
        3)
            audio_source="voice-call-uplink"
            ;;
        b|B)
            return 0
            ;;
        *)
            echo "Invalid input, returning to main menu."
            action_pause
            return 0
            ;;
    esac

    scrcpy -s "$selected" --audio-source="$audio_source" --no-video
}

selected_config() {
    clear
    echo "[Settings]"
    echo
    echo "Current profile: ${selected_profile}"
    echo
    echo "Available profiles:"

    local profiles=()
    local name choice i=0
    while IFS= read -r name; do
        [ -z "$name" ] && continue
        profiles+=("$name")
        i=$((i + 1))
        echo "$i. $name"
    done < <(list_profiles)

    if [ "$i" -eq 0 ]; then
        echo "No available profiles found."
        action_pause
        return 0
    fi

    echo
    read -r -p "Enter profile number (press Enter to cancel): " choice
    [ -z "$choice" ] && return 0

    if ! [[ "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 1 ] || [ "$choice" -gt "$i" ]; then
        echo "Invalid input, returning to settings menu."
        action_pause
        return 0
    fi

    selected_profile="${profiles[$((choice - 1))]}"
    if save_selected_profile "$selected_profile"; then
        load_config
        echo "Selected: $selected_profile"
    else
        echo "Failed to save profile."
    fi
    action_pause
}

main_menu() {
    while true; do
        clear
        echo "[Scrcpy Mirroring]"
        echo
        echo "1. Screen Mirroring"
        echo "2. Camera Mirroring"
        echo "3. Microphone Audio"
        echo "4. Call Audio"
        echo "5. Settings"
        echo "6. Exit"
        echo

        read -r -p "Enter option number: " menu

        case "$menu" in
            1)
                clear
                echo "[Screen Mirroring]"
                echo "Detecting devices..."
                echo
                if choose_device; then
                    display_mirror
                fi
                ;;
            2)
                clear
                echo "[Camera Mirroring]"
                echo "Detecting devices..."
                echo
                if choose_device; then
                    cam_mirror
                fi
                ;;
            3)
                clear
                echo "[Microphone Audio]"
                echo "Detecting devices..."
                echo
                if choose_device; then
                    mic_audio
                fi
                ;;
            4)
                clear
                echo "[Call Audio]"
                echo "Detecting devices..."
                echo
                if choose_device; then
                    call_audio
                fi
                ;;
            5)
                selected_config
                ;;
            6)
                exit 0
                ;;
            *)
                echo "Invalid input. Please select again."
                action_pause
                ;;
        esac
    done
}

check_deps
load_config
main_menu
