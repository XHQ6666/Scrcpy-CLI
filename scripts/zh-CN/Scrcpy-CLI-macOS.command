#!/bin/bash

CONFIG_FILE="$HOME/scrcpy_config.json"
selected_profile=""
dsp_args_str=""
cam_args_str=""

dsp_args_array=()
cam_args_array=()

action_pause() {
    read -r -p "按回车继续..." _
}

check_deps() {
    local missing=0
    for cmd in adb scrcpy python3; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            echo "未找到命令：$cmd"
            missing=1
        fi
    done

    if [ "$missing" -ne 0 ]; then
        echo
        echo "请先安装依赖，例如："
        echo "  brew install android-platform-tools scrcpy"
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
        echo "没有检测到已连接的设备！"
        action_pause
        return 1
    fi

    if [ "$count" -eq 1 ]; then
        selected="${devices[0]}"
        selected_status="${statuses[0]}"
        echo "检测到一个设备：$selected 状态：$selected_status"
        echo "开始连接..."
        sleep 2
    else
        echo "检测到 ${count} 个设备，请选择："
        local i label choice
        for ((i=0; i<count; i++)); do
            label="[${statuses[$i]}]"
            case "${statuses[$i]}" in
                device) label="[在线]" ;;
                unauthorized) label="[未授权]" ;;
                offline) label="[离线]" ;;
            esac
            echo "$((i + 1)). ${devices[$i]} $label"
        done

        echo
        read -r -p "请输入设备编号：" choice
        if ! [[ "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 1 ] || [ "$choice" -gt "$count" ]; then
            echo "输入无效，返回主菜单"
            action_pause
            return 1
        fi

        selected="${devices[$((choice - 1))]}"
        selected_status="${statuses[$((choice - 1))]}"
    fi

    if [ "$selected_status" = "offline" ]; then
        echo "设备为离线状态，尝试重新连接..."
        adb disconnect "$selected"
        adb connect "$selected"
        echo "已尝试重新连接，请检查设备是否在线"
        action_pause
        return 1
    fi

    return 0
}

display_mirror() {
    clear
    echo "[屏幕镜像]"
    scrcpy -s "$selected" "${dsp_args_array[@]}"
}

cam_mirror() {
    clear
    echo "[相机镜像]"
    echo

    local cam cam_direction
    read -r -p "选择摄像头 ID（输入 b 返回）：" cam
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
    echo "[麦克风音频]"
    scrcpy -s "$selected" --audio-source=mic --no-video
}

selected_config() {
    clear
    echo "[参数设置]"
    echo
    echo "当前配置：${selected_profile}"
    echo
    echo "可用配置："

    profiles=()
    local name choice i=0
    while IFS= read -r name; do
        [ -z "$name" ] && continue
        profiles+=("$name")
        i=$((i + 1))
        echo "$i. $name"
    done < <(list_profiles)

    if [ "$i" -eq 0 ]; then
        echo "未发现可用配置。"
        action_pause
        return 0
    fi

    echo
    read -r -p "请输入配置编号（回车取消）：" choice
    [ -z "$choice" ] && return 0

    if ! [[ "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 1 ] || [ "$choice" -gt "$i" ]; then
        echo "输入无效，返回配置菜单"
        action_pause
        return 0
    fi

    selected_profile="${profiles[$((choice - 1))]}"
    if save_selected_profile "$selected_profile"; then
        load_config
        echo "已选择：$selected_profile"
    else
        echo "保存配置失败。"
    fi
    action_pause
}

main_menu() {
    while true; do
        clear
        echo "[Scrcpy 投屏]"
        echo
        echo "1. 屏幕镜像"
        echo "2. 相机镜像"
        echo "3. 麦克风音频"
        echo "4. 参数设置"
        echo "5. 退出"
        echo

        read -r -p "请输入选项编号：" menu

        case "$menu" in
            1)
                clear
                echo "[屏幕镜像]"
                echo "正在检测设备..."
                echo
                if choose_device; then
                    display_mirror
                fi
                ;;
            2)
                clear
                echo "[相机镜像]"
                echo "正在检测设备..."
                echo
                if choose_device; then
                    cam_mirror
                fi
                ;;
            3)
                clear
                echo "[麦克风音频]"
                echo "正在检测设备..."
                echo
                if choose_device; then
                    mic_audio
                fi
                ;;
            4)
                selected_config
                ;;
            5)
                exit 0
                ;;
            *)
                echo "输入无效，请重新选择。"
                action_pause
                ;;
        esac
    done
}

check_deps
load_config
main_menu
