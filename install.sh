#!/usr/bin/env bash
set -euo pipefail

# ----------------------------
# CONFIG (set these)
# ----------------------------
REPO_URL="https://github.com/Grelwing/arch-dots-base.git"
REPO_DIR="${HOME}/arch-dots-base"

PACMAN_LIST_REL="pkg/pacman.txt"
AUR_LIST_REL="pkg/aur.txt"

die(){ echo "ERROR: $*" >&2; exit 1; }

sudo_keepalive() {
  sudo -v
  while true; do sudo -n true; sleep 30; kill -0 "$$" || exit; done 2>/dev/null &
}

choose_aur_helper() {
  echo "User Choice: Yay/Paru"
  echo "1) yay"
  echo "2) paru"
  read -r -p "Select [1-2]: " choice
  case "$choice" in
    1) echo "yay" ;;
    2) echo "paru" ;;
    *) die "Invalid selection." ;;
  esac
}

install_aur_helper_from_aur() {
  local helper="$1"

  if command -v "$helper" >/dev/null 2>&1; then
    echo "[*] $helper already installed."
    return
  fi

  echo "[*] Installing AUR helper: $helper"
  sudo pacman -S --needed --noconfirm git base-devel

  local tmp
  tmp="$(mktemp -d)"
  pushd "$tmp" >/dev/null

  if [[ "$helper" == "yay" ]]; then
    git clone https://aur.archlinux.org/yay.git
    cd yay
  else
    git clone https://aur.archlinux.org/paru.git
    cd paru
  fi

  makepkg -si --noconfirm
  popd >/dev/null
  rm -rf "$tmp"
}

clone_or_update_repo() {
  if [[ -d "${REPO_DIR}/.git" ]]; then
    echo "[*] Repo exists, pulling latest..."
    git -C "$REPO_DIR" pull
  else
    echo "[*] Cloning repo..."
    git clone "$REPO_URL" "$REPO_DIR"
  fi
}

read_pkg_list() {
  local path="$1"
  [[ -f "$path" ]] || die "Missing package list: $path"

  # strip comments + blanks
  sed -e 's/#.*$//' -e '/^[[:space:]]*$/d' "$path"
}

install_pacman_list() {
  local list_path="${REPO_DIR}/${PACMAN_LIST_REL}"
  echo
  echo "#Pacman (from ${PACMAN_LIST_REL})"
  read_pkg_list "$list_path" | sed 's/^/  /'

  echo "[*] Updating system..."
  sudo pacman -Syu --noconfirm

  echo "[*] Installing pacman packages (skips already-installed)..."
  mapfile -t pkgs < <(read_pkg_list "$list_path")
  sudo pacman -S --needed --noconfirm "${pkgs[@]}"
}

install_aur_list() {
  local helper="$1"
  local list_path="${REPO_DIR}/${AUR_LIST_REL}"

  echo
  echo "#AUR (from ${AUR_LIST_REL})"
  read_pkg_list "$list_path" | sed 's/^/  /'

  echo "[*] Installing AUR packages (skips already-installed)..."
  mapfile -t pkgs < <(read_pkg_list "$list_path")
  "$helper" -S --needed --noconfirm "${pkgs[@]}"
}

backup_path() {
  local path="$1"
  if [[ -e "$path" || -L "$path" ]]; then
    local ts
    ts="$(date +%Y%m%d-%H%M%S)"
    local bak="${path}.bak.${ts}"
    echo "[*] Backing up: $path -> $bak"
    mv "$path" "$bak"
  fi
}

restore_rice_copy() {
  echo
  echo "[*] Restoring rice (COPY staged home/ into real \$HOME)..."
  local staged_home="${REPO_DIR}/home"
  [[ -d "$staged_home" ]] || die "Missing repo directory: ${staged_home}"

  # copy .config subdirs
  if [[ -d "${staged_home}/.config" ]]; then
    mkdir -p "$HOME/.config"
    for d in "${staged_home}/.config/"*; do
      [[ -e "$d" ]] || continue
      local name
      name="$(basename "$d")"
      backup_path "$HOME/.config/$name"
      rsync -a "$d/" "$HOME/.config/$name/"
    done
  fi

  # scripts
  if [[ -d "${staged_home}/.local/bin" ]]; then
    mkdir -p "$HOME/.local/bin"
    rsync -a "${staged_home}/.local/bin/" "$HOME/.local/bin/"
  fi

  # themes + icons
  if [[ -d "${staged_home}/.themes" ]]; then
    mkdir -p "$HOME/.themes"
    rsync -a "${staged_home}/.themes/" "$HOME/.themes/"
  fi

  if [[ -d "${staged_home}/.icons" ]]; then
    mkdir -p "$HOME/.icons"
    rsync -a "${staged_home}/.icons/" "$HOME/.icons/"
  fi

  # wallpapers
  if [[ -d "${staged_home}/Pictures/Wallpapers" ]]; then
    mkdir -p "$HOME/Pictures"
    rsync -a "${staged_home}/Pictures/Wallpapers/" "$HOME/Pictures/Wallpapers/"
  fi
}

apply_system_overrides() {
  echo
  echo "[*] Applying system overrides (repo etc/ -> /etc)..."
  local staged_etc="${REPO_DIR}/etc"
  [[ -d "$staged_etc" ]] || { echo "[*] No etc/ directory; skipping."; return; }

  # SDDM override
  if [[ -d "${staged_etc}/sddm.conf.d" ]]; then
    sudo mkdir -p /etc/sddm.conf.d
    sudo rsync -a "${staged_etc}/sddm.conf.d/" /etc/sddm.conf.d/
  fi
}

main() {
  sudo_keepalive

  # clone first so lists are the source of truth
  sudo pacman -S --needed --noconfirm git rsync
  clone_or_update_repo

  install_pacman_list

  local helper
  helper="$(choose_aur_helper)"
  install_aur_helper_from_aur "$helper"
  install_aur_list "$helper"

  restore_rice_copy
  apply_system_overrides

  echo
  echo "[✓] Complete."
  echo "If you intend to use SDDM and it isn't enabled:"
  echo "  sudo systemctl enable --now sddm"
  echo "Log out or reboot to ensure everything reloads cleanly."
}

main "$@"
