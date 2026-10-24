#!/usr/bin/env bash
#
#  MacShell Universal Installer & Setup Assistant (Arch Linux / Hyprland)
#
# One-line Quick Install:
#   sh -c "$(curl -fsSL https://raw.githubusercontent.com/4sakenme/MacOsSHell-New/main/install.sh)"
#
# Or run from local repository:
#   ./install.sh
#

set -eo pipefail

# ── Color Palette ──
BOLD="\033[1m"
DIM="\033[2m"
BLUE="\033[1;34m"
GREEN="\033[1;32m"
AMBER="\033[1;33m"
RED="\033[1;31m"
CYAN="\033[1;36m"
NC="\033[0m"

log_info() { echo -e "  ${BLUE}●${NC} $1"; }
log_ok()   { echo -e "  ${GREEN}✓${NC} $1"; }
log_warn() { echo -e "  ${AMBER}!${NC} $1"; }
log_err()  { echo -e "  ${RED}✕${NC} $1"; }

banner() {
    clear 2>/dev/null || true
    echo -e "${BLUE}"
    cat <<'EOF'
    __  ___           _____ __          ____
   /  |/  /___ ______/ ___// /_  ___   / / /
  / /|_/ / __ `/ ___/\__ \/ __ \/ _ \ / / / 
 / /  / / /_/ / /__ ___/ / / / /  __// / /  
/_/  /_/\__,_/\___//____/_/ /_/\___//_/_/   
EOF
    echo -e "${NC}"
    echo -e "  ${BOLD} MacShell Universal Installer${NC} ${DIM}· macOS Experience on Arch Linux & Hyprland${NC}"
    echo -e "  ${DIM}─────────────────────────────────────────────────────────────────${NC}\n"
}

need_cmd() {
    command -v "$1" >/dev/null 2>&1
}

# ── Doctor Diagnostics Mode ──
run_doctor() {
    echo -e "\n  ${BOLD} MacShell System Diagnostics (Doctor)${NC}\n"
    
    # 1. OS & Kernel
    log_info "Operating System: $(uname -s) $(uname -r) ($(uname -m))"
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        log_ok "Distribution: ${PRETTY_NAME:-$NAME}"
    fi

    # 2. Wayland & Hyprland
    if [ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]; then
        log_ok "Hyprland session active (Signature: ${HYPRLAND_INSTANCE_SIGNATURE:0:8}...)"
        if need_cmd hyprctl; then
            HL_VER=$(hyprctl version 2>/dev/null | head -n1 || echo "unknown")
            log_ok "Hyprland version: $HL_VER"
        fi
    elif [ -n "${WAYLAND_DISPLAY:-}" ]; then
        log_warn "Wayland session active ($WAYLAND_DISPLAY), but Hyprland signature not found."
    else
        log_err "No Wayland / Hyprland session detected."
    fi

    # 3. Quickshell
    if need_cmd quickshell; then
        QS_VER=$(quickshell --version 2>/dev/null | head -n1 || echo "installed")
        log_ok "Quickshell: $QS_VER"
    elif need_cmd qs; then
        log_ok "Quickshell (qs) is installed."
    else
        log_err "Quickshell is not installed."
    fi

    # 4. Audio & Network
    if need_cmd pw-play || need_cmd pipewire; then
        log_ok "Audio Engine: PipeWire active"
    else
        log_warn "PipeWire audio tools not detected."
    fi

    if need_cmd nmcli; then
        log_ok "Network Manager: NetworkManager (nmcli) available"
    elif need_cmd iwctl; then
        log_ok "Network Manager: iwd (iwctl) available"
    else
        log_warn "No wireless network manager CLI found (install networkmanager)."
    fi

    # 5. Fonts
    if need_cmd fc-list; then
        if fc-list : family | grep -qiE "SF Pro|Open Runde|Inter"; then
            log_ok "Typography: Apple SF Pro / Open Runde fonts available"
        else
            log_warn "Apple typography fonts not found in system font cache."
        fi
    fi
    echo ""
    exit 0
}

# ── Parse Command Line Arguments ──
MODE="gui"
for arg in "$@"; do
    case "$arg" in
        --doctor)
            run_doctor
            ;;
        --cli|--no-gui|-c)
            MODE="cli"
            ;;
        --help|-h)
            echo "Usage: ./install.sh [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  (default)     Launch macOS Setup Assistant (OOBE) GUI"
            echo "  --cli         Run headless non-interactive installation"
            echo "  --doctor      Run diagnostic health check on your environment"
            echo "  --help, -h    Display this help message"
            echo ""
            exit 0
            ;;
    esac
done

banner

# ── Upfront Administrative Authentication (sudo) ──
log_info "Verifying administrative privileges (sudo) upfront..."
if ! sudo -v; then
    log_err "Administrative privileges (sudo) are required for installation."
    exit 1
fi
# Keep sudo timestamp updated in background while install.sh runs
( while true; do sudo -n true; sleep 50; kill -0 "$$" || exit; done ) 2>/dev/null &
SUDO_KEEP_ALIVE_PID=$!
trap 'kill "$SUDO_KEEP_ALIVE_PID" 2>/dev/null || true' EXIT
log_ok "Root access verified."

# ── 1. Environment & Distribution Verification ──
log_info "Verifying system environment..."

if [ "$(uname -s)" != "Linux" ]; then
    log_err "MacShell is only supported on Linux operating systems."
    exit 1
fi

DISTRO="linux"
PKG_MGR="unknown"

if [ -f /etc/os-release ]; then
    . /etc/os-release
    DISTRO="${ID:-linux}"
    log_ok "Detected distribution: ${PRETTY_NAME:-$NAME} ($DISTRO)"
fi

if command -v pacman >/dev/null 2>&1; then
    PKG_MGR="pacman"
elif command -v dnf >/dev/null 2>&1; then
    PKG_MGR="dnf"
elif command -v apt-get >/dev/null 2>&1; then
    PKG_MGR="apt"
elif command -v zypper >/dev/null 2>&1; then
    PKG_MGR="zypper"
fi

install_pkg() {
    local p="$1"
    case "$PKG_MGR" in
        pacman)
            sudo pacman -S --needed --noconfirm "$p"
            ;;
        dnf)
            sudo dnf install -y "$p"
            ;;
        apt)
            sudo apt-get update -qq && sudo apt-get install -y "$p"
            ;;
        zypper)
            sudo zypper --non-interactive in "$p"
            ;;
        *)
            log_warn "Unknown package manager. Please install '$p' using your distribution tools."
            ;;
    esac
}

if [ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]; then
    log_ok "Hyprland is already running. Shell can launch directly."
elif [ -n "${WAYLAND_DISPLAY:-}" ]; then
    log_ok "Running on active Wayland session ($WAYLAND_DISPLAY)."
else
    log_warn "No active Wayland/Hyprland session detected."
    log_warn "Running inside an active Hyprland session is strongly recommended for Liquid Glass shaders."
    if [ "$MODE" = "gui" ]; then
        echo -en "  ${AMBER}? Continue launching installer anyway? [y/N]: ${NC}"
        read -r ans
        if [[ ! "$ans" =~ ^[yY]$ ]]; then
            echo "Installation canceled."
            exit 0
        fi
    fi
fi

# ── 2. Check & Install Essential Dependencies ──
log_info "Checking minimum bootstrap dependencies..."

if [ "$PKG_MGR" = "pacman" ]; then
    log_info "Synchronizing core packages via pacman..."
    sudo pacman -S --needed --noconfirm git curl python3 python-pillow librsvg rsync tar xz networkmanager pipewire wireplumber 2>/dev/null || true
elif [ "$PKG_MGR" = "dnf" ]; then
    log_info "Synchronizing core packages via dnf..."
    sudo dnf install -y git curl python3 python3-pillow librsvg2-tools rsync tar xz NetworkManager pipewire wireplumber 2>/dev/null || true
elif [ "$PKG_MGR" = "apt" ]; then
    log_info "Synchronizing core packages via apt..."
    sudo apt-get update -qq && sudo apt-get install -y git curl python3 python3-pil librsvg2-bin rsync tar xz-utils network-manager pipewire wireplumber 2>/dev/null || true
fi

for pkg in git curl python3; do
    if need_cmd "$pkg"; then
        log_ok "$pkg is available."
    else
        log_info "Installing package $pkg via $PKG_MGR..."
        install_pkg "$pkg"
    fi
done

# Check Quickshell
if need_cmd quickshell || need_cmd qs; then
    log_ok "Quickshell is installed ($(quickshell --version 2>/dev/null | head -n1 || echo 'ready'))."
else
    log_info "Quickshell not found. Detecting installation method for $DISTRO..."
    if [ "$PKG_MGR" = "pacman" ]; then
        AUR_HELPER=""
        if need_cmd yay; then
            AUR_HELPER="yay"
        elif need_cmd paru; then
            AUR_HELPER="paru"
        fi

        if [ -n "$AUR_HELPER" ]; then
            log_info "Installing quickshell-git via $AUR_HELPER..."
            $AUR_HELPER -S --needed --noconfirm quickshell-git
        else
            log_warn "Neither yay nor paru found. Building yay-bin from AUR..."
            TMP_YAY=$(mktemp -d)
            git clone --depth 1 https://aur.archlinux.org/yay-bin.git "$TMP_YAY"
            (cd "$TMP_YAY" && makepkg -si --noconfirm)
            rm -rf "$TMP_YAY"
            yay -S --needed --noconfirm quickshell-git
        fi
    elif [ "$PKG_MGR" = "dnf" ]; then
        log_info "Enabling COPR repository for quickshell on Fedora..."
        sudo dnf copr enable -y vsoultann/quickshell || true
        sudo dnf install -y quickshell
    else
        log_warn "Quickshell is required to run the shell interface."
        log_warn "Please install Quickshell from: https://quickshell.org/download/"
    fi
fi

# ── 3. Install Authentic macOS Cursor Pack (apple_cursor) ──
USER_ICONS_DIR="$HOME/.local/share/icons"
SYS_ICONS_DIR="/usr/share/icons"
mkdir -p "$USER_ICONS_DIR"

if [ ! -d "$USER_ICONS_DIR/macOS" ] && [ ! -d "$SYS_ICONS_DIR/macOS" ]; then
    log_info "Downloading authentic Apple cursor pack (ful1e5/apple_cursor)..."
    TMP_CURSOR=$(mktemp -d)
    if curl -fsSL -o "$TMP_CURSOR/macOS.tar.xz" "https://github.com/ful1e5/apple_cursor/releases/latest/download/macOS.tar.xz"; then
        tar -xJf "$TMP_CURSOR/macOS.tar.xz" -C "$TMP_CURSOR/"
        cp -r "$TMP_CURSOR/macOS" "$TMP_CURSOR/macOS-White" "$USER_ICONS_DIR/" 2>/dev/null || true
        sudo cp -r "$TMP_CURSOR/macOS" "$TMP_CURSOR/macOS-White" "$SYS_ICONS_DIR/" 2>/dev/null || true
        log_ok "macOS cursor pack installed (macOS & macOS-White)."
    else
        log_warn "Could not download apple_cursor archive. Falling back to default system cursor."
    fi
    rm -rf "$TMP_CURSOR"
else
    log_ok "macOS cursor pack already available."
fi

# Apply cursor theme to GTK and Hyprland
gsettings set org.gnome.desktop.interface cursor-theme 'macOS' 2>/dev/null || true
if need_cmd hyprctl; then
    hyprctl setcursor macOS 24 2>/dev/null || true
fi

# ── 4. Install macOS Tahoe Icon Theme (Scrimas/MacOS-Like) ──
if [ ! -d "$USER_ICONS_DIR/MacOS-Like-Dark" ] && [ ! -d "$SYS_ICONS_DIR/MacOS-Like-Dark" ]; then
    log_info "Downloading and building macOS Tahoe icon theme (Scrimas/MacOS-Like)..."
    TMP_ICONS=$(mktemp -d)
    if git clone --depth 1 "https://github.com/Scrimas/MacOS-Like.git" "$TMP_ICONS/MacOS-Like"; then
        (cd "$TMP_ICONS/MacOS-Like" && bash setup.sh --force) || log_warn "MacOS-Like setup script reported warnings."
        if [ -d "$USER_ICONS_DIR/MacOS-Like-Dark" ]; then
            sudo cp -ru "$USER_ICONS_DIR/MacOS-Like"* "$SYS_ICONS_DIR/" 2>/dev/null || true
            log_ok "macOS Tahoe icon theme (MacOS-Like) installed successfully."
        fi
    else
        log_warn "Could not clone Scrimas/MacOS-Like repository."
    fi
    rm -rf "$TMP_ICONS"
else
    log_ok "macOS Tahoe icon theme (MacOS-Like) is already installed."
fi

# Apply icon theme in GTK
gsettings set org.gnome.desktop.interface icon-theme 'MacOS-Like-Dark' 2>/dev/null || true

# ── 5. Locate / Download MacShell Source ──
BOOTSTRAP_DIR="$HOME/.cache/macshell-bootstrap"
REPO_URL="https://github.com/4sakenme/MacOsSHell-New.git"

mkdir -p "$BOOTSTRAP_DIR"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"

if [ -f "$SCRIPT_DIR/MacShell/SetupAssistant.qml" ]; then
    log_info "Local repository detected at $SCRIPT_DIR, synchronizing..."
    mkdir -p "$BOOTSTRAP_DIR/repo"
    cp -ru "$SCRIPT_DIR"/* "$BOOTSTRAP_DIR/repo/" 2>/dev/null || true
else
    if [ -d "$BOOTSTRAP_DIR/repo/.git" ]; then
        log_info "Updating Setup Assistant resources from GitHub..."
        git -C "$BOOTSTRAP_DIR/repo" fetch --depth 1 origin main || true
        git -C "$BOOTSTRAP_DIR/repo" reset --hard origin/main || true
    else
        log_info "Cloning Setup Assistant from GitHub..."
        rm -rf "$BOOTSTRAP_DIR/repo"
        git clone --depth 1 "$REPO_URL" "$BOOTSTRAP_DIR/repo"
    fi
fi

REPO_ROOT="$BOOTSTRAP_DIR/repo"

# ── 6. Execution (GUI vs CLI Mode) ──
CONFIG_DEST="$HOME/.config/quickshell/MacShell"
LOCK_DEST="$HOME/.config/quickshell/MacLock"
mkdir -p "$HOME/.config/quickshell" "$HOME/.config/macshell" "$CONFIG_DEST" "$LOCK_DEST"

# Deploy MacShell components directly into $CONFIG_DEST (never nested)
if [ -d "$REPO_ROOT/MacShell" ]; then
    cp -ru "$REPO_ROOT/MacShell"/* "$CONFIG_DEST/" 2>/dev/null || true
fi

# Flatten any nested MacShell directory if accidentally present
if [ -d "$CONFIG_DEST/MacShell" ] && [ "$CONFIG_DEST/MacShell" != "$CONFIG_DEST" ] && [ -f "$CONFIG_DEST/MacShell/shell.qml" ]; then
    log_warn "Detected nested MacShell directory. Flattening structure..."
    cp -ru "$CONFIG_DEST/MacShell"/* "$CONFIG_DEST/"
    rm -rf "$CONFIG_DEST/MacShell"
fi

# Deploy MacLock components directly into $LOCK_DEST
if [ -d "$REPO_ROOT/MacLock" ]; then
    cp -ru "$REPO_ROOT/MacLock"/* "$LOCK_DEST/" 2>/dev/null || true
fi
if [ -f "$LOCK_DEST/MacLock/MacLock.qml" ]; then
    cp -ru "$LOCK_DEST/MacLock"/* "$LOCK_DEST/"
    rm -rf "$LOCK_DEST/MacLock"
fi

# Integrity check: verify core files exist directly inside $CONFIG_DEST
for f in shell.qml MacBar.qml MacDock.qml StageManager.qml; do
    if [ ! -f "$CONFIG_DEST/$f" ]; then
        log_err "Integrity check failed: $f missing in $CONFIG_DEST."
        exit 1
    fi
done
log_ok "Integrity verified: shell.qml, MacBar.qml, MacDock.qml, StageManager.qml are directly in $CONFIG_DEST"

if [ "$MODE" = "cli" ]; then
    log_info "Running non-interactive CLI installation..."
    touch "$HOME/.config/macshell/.setup_completed"
    touch "$CONFIG_DEST/.setup_completed"
    
    # Run setup worker
    if [ -f "$CONFIG_DEST/scripts/setup_assistant_worker.py" ]; then
        python3 "$CONFIG_DEST/scripts/setup_assistant_worker.py" run_setup '{"siri":false,"sound_pack":true,"wifi_manager":true}'
    fi
    log_ok "Installation completed in CLI mode. Launch with: quickshell -c MacShell"
    exit 0
fi

SETUP_QML="$CONFIG_DEST/SetupAssistant.qml"
if [ ! -f "$SETUP_QML" ]; then
    SETUP_QML="$REPO_ROOT/MacShell/SetupAssistant.qml"
fi

if [ ! -f "$SETUP_QML" ]; then
    log_err "Could not find SetupAssistant.qml."
    exit 1
fi

log_ok "Bootstrap ready. Launching macOS Setup Assistant..."
echo -e "\n  ${CYAN}✨ Opening macOS Setup Assistant on your screen...${NC}\n"

# Run quickshell pointing to SetupAssistant.qml
quickshell -p "$SETUP_QML"
