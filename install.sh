#!/usr/bin/env bash
set -Eeuo pipefail

# Install automatic display resizing on Arch Linux with SPICE/i3.
# Run as a regular user, never as root.

info() { printf '\n[INFO] %s\n' "$*"; }
die() { printf '[ERROR] %s\n' "$*" >&2; exit 1; }

[[ $EUID -ne 0 ]] || die 'Run as a regular user, not root.'
for cmd in pacman sudo git; do
  if [[ $cmd == git ]]; then continue; fi
  command -v "$cmd" >/dev/null 2>&1 || die "Missing command: $cmd"
done
[[ -r /dev/tty && -w /dev/tty ]] || die 'An interactive terminal is required.'

info 'Installing required packages...'
sudo pacman -Syu --needed git base-devel xorg-xrandr </dev/tty

if ! command -v yay >/dev/null 2>&1; then
  info 'Installing yay-bin from AUR...'
  build_dir=$(mktemp -d)
  trap 'rm -rf "$build_dir"' EXIT
  git clone https://aur.archlinux.org/yay-bin.git "$build_dir/yay-bin"
  info 'Review the AUR build files before continuing:'
  (cd "$build_dir/yay-bin" && less PKGBUILD) </dev/tty
  printf 'Install yay-bin after reviewing its PKGBUILD? [y/N] ' >/dev/tty
  read -r reply </dev/tty
  [[ $reply == [yY] || $reply == [yY][eE][sS] ]] || die 'Installation cancelled.'
  (cd "$build_dir/yay-bin" && makepkg -si) </dev/tty
fi

if pacman -Q x-resize >/dev/null 2>&1; then
  info 'x-resize is already installed.'
else
  info 'Installing x-resize from AUR (review the PKGBUILD and diffs when prompted)...'
  yay -S --needed x-resize </dev/tty
fi

info 'Installation complete. Restart the VM and enable auto-resize in virt-manager.'
