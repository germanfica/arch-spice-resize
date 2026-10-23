
#!/usr/bin/env bash
set -Eeuo pipefail

# Install automatic SPICE display resizing on Omarchy/Hyprland.
# Run as a regular user, never as root.

info() { printf '\n[INFO] %s\n' "$*"; }
die() { printf '[ERROR] %s\n' "$*" >&2; exit 1; }

[[ $EUID -ne 0 ]] || die 'Run as a regular user, not root.'

for cmd in pacman sudo hyprctl; do
  command -v "$cmd" >/dev/null 2>&1 || die "Missing command: $cmd"
done

[[ ${XDG_SESSION_TYPE:-} == wayland ]] || die 'Wayland session required.'
hyprctl monitors >/dev/null 2>&1 || die 'Hyprland is not running.'

info 'Installing SPICE guest agent...'
sudo pacman -S --needed spice-vdagent

info 'Installing automatic display resize helper...'

bin_dir="$HOME/.local/bin"
helper="$bin_dir/omarchy-spice-resize"

mkdir -p "$bin_dir"

cat > "$helper" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail

# Follow Virtio-GPU DRM preferred modes in Hyprland.

command -v hyprctl >/dev/null 2>&1 || exit 1
command -v flock >/dev/null 2>&1 || exit 1

runtime_dir="${XDG_RUNTIME_DIR:-/run/user/$UID}"
exec 9>"$runtime_dir/omarchy-spice-resize.lock"
flock -n 9 || exit 0

declare -A previous_modes

while true; do
  for path in /sys/class/drm/card*-Virtual-*/modes; do
    [[ -r $path ]] || continue

    output="${path%/modes}"
    output="${output##*-}"

    # Convert DRM path to Hyprland monitor name.
    # For example: card0-Virtual-1 -> Virtual-1
    connector="${path%/modes}"
    connector="${connector##*/}"
    monitor="${connector#*-}"

    hyprctl monitors | grep -Fq "Monitor $monitor (" || continue

    read -r mode < "$path" || continue
    [[ $mode =~ ^[0-9]+x[0-9]+$ ]] || continue

    [[ ${previous_modes[$monitor]:-} == "$mode" ]] && continue

    if hyprctl keyword monitor "$monitor,$mode,auto,1" >/dev/null; then
      previous_modes[$monitor]="$mode"
    fi
  done

  sleep 1
done
EOF

chmod +x "$helper"

info 'Configuring Omarchy autostart...'

autostart="$HOME/.config/hypr/autostart.lua"
mkdir -p "$(dirname "$autostart")"
touch "$autostart"

if ! grep -Fq 'omarchy-spice-resize' "$autostart"; then
  printf '\n-- Automatic SPICE display resizing\n' >> "$autostart"
  printf 'o.launch_on_start("%s")\n' "$helper" >> "$autostart"
fi

info 'Starting resize helper...'
nohup "$helper" >/dev/null 2>&1 </dev/null &

info 'Installation complete.'
info 'Enable automatic VM resizing in virt-manager.'
