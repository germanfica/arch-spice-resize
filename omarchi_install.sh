#!/usr/bin/env bash
set -Eeuo pipefail

# Virtio-GPU window resize synchronization for Omarchy 4 / Hyprland.
# No SPICE agent changes. Run as the desktop user, not root.
trap 'printf "\n[ERROR] Installation failed at line %s.\n" "$LINENO" >&2' ERR
info() { printf '\n[INFO] %s\n' "$*"; }
die() { printf '[ERROR] %s\n' "$*" >&2; exit 1; }

(( EUID != 0 )) || die 'Run as a regular user.'
[[ ${XDG_SESSION_TYPE:-} == wayland ]] || die 'A Wayland session is required.'
for cmd in hyprctl jq flock; do
  command -v "$cmd" >/dev/null 2>&1 || die "Missing command: $cmd"
done
hyprctl -j monitors >/dev/null 2>&1 || die 'Hyprland is not available.'

found=false
for path in /sys/class/drm/card*-Virtual-*/modes; do
  if [[ -r $path ]]; then found=true; break; fi
done
$found || die 'No Virtio-GPU Virtual-* DRM connector found. Check virt-manager video device (Virtio) first.'

bin_dir="${HOME}/.local/bin"
helper="${bin_dir}/omarchy-spice-resize"
mkdir -p "$bin_dir"
cat > "$helper" <<'HELPER'
#!/usr/bin/env bash
set -Eeuo pipefail

runtime_dir="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
mkdir -p "$runtime_dir"
log="$runtime_dir/omarchy-spice-resize.log"
exec 9>"$runtime_dir/omarchy-spice-resize.lock"
flock -n 9 || exit 0

log_msg() { printf '[%(%F %T)T] %s\n' -1 "$*" >> "$log"; }
log_msg 'Watcher started.'
declare -A last_modes=()

while true; do
  if ! monitors_json=$(hyprctl -j monitors 2>/dev/null); then
    log_msg 'Cannot contact Hyprland; retrying.'
    sleep 2
    continue
  fi

  for path in /sys/class/drm/card*-Virtual-*/modes; do
    [[ -r $path ]] || continue
    connector=${path%/modes}
    connector=${connector##*/}
    monitor=${connector#*-}

    # Only manage active Hyprland virtual outputs.
    if ! jq -e --arg m "$monitor" 'any(.[]; .name == $m)' <<< "$monitors_json" >/dev/null; then
      continue
    fi

    IFS= read -r mode < "$path" || true
    [[ $mode =~ ^[0-9]+x[0-9]+$ ]] || continue

    current=$(jq -r --arg m "$monitor" '.[] | select(.name == $m) | "\(.width)x\(.height)"' <<< "$monitors_json" | head -n 1)
    [[ $mode == "${last_modes[$monitor]:-}" && $mode == "$current" ]] && continue

    if [[ $current == "$mode" ]]; then
      last_modes[$monitor]="$mode"
      continue
    fi

    # Omarchy 4 uses Hyprland's Lua configuration interface.
    rule="hl.monitor({ output = \"${monitor}\", mode = \"${mode}\", position = \"auto\", scale = 1 })"
    if output=$(hyprctl eval "$rule" 2>&1); then
      log_msg "Applied $monitor: $current -> $mode"
      last_modes[$monitor]="$mode"
    else
      log_msg "Failed $monitor -> $mode: $output"
    fi
  done
  sleep 1
done
HELPER
chmod 755 "$helper"

# The previous installer already used this autostart entry. Reuse rather than duplicate it.
autostart="${HOME}/.config/hypr/autostart.lua"
if [[ -f "$autostart" ]] && grep -Fq 'omarchy-spice-resize' "$autostart"; then
  info 'Existing Omarchy autostart entry found; keeping it.'
else
  mkdir -p "$(dirname "$autostart")"
  printf '\n-- Automatic Virtio-GPU window resize\no.launch_on_start("%s")\n' "$helper" >> "$autostart"
  info 'Added Omarchy autostart entry.'
fi

# Stop only the previous helper; leave SPICE/clipboard services untouched.
if command -v pkill >/dev/null 2>&1; then
  pkill -u "$(id -u)" -f '^bash /home/.*/omarchy-spice-resize$' 2>/dev/null || true
  pkill -u "$(id -u)" -f "^bash ${helper}$" 2>/dev/null || true
fi
nohup "$helper" >/dev/null 2>&1 </dev/null &
info 'Installed and started watcher. Resize virt-manager window to test.'
info "Log: ${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/omarchy-spice-resize.log"
info 'Needs Virtio-GPU DRM modes to update when the viewer window changes.'
