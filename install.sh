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

# ── 2. Check & Install Essential Dependencies (git, curl, python3, quickshell) ──
log_info "Checking minimum bootstrap dependencies..."

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

# ── 3. Locate / Download MacShell Source ──
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

# ── 4. Execution (GUI vs CLI Mode) ──
if [ "$MODE" = "cli" ]; then
    log_info "Running non-interactive CLI installation..."
    CONFIG_DEST="$HOME/.config/quickshell/MacShell"
    mkdir -p "$HOME/.config/quickshell" "$HOME/.config/macshell"
    
    if [ ! -d "$CONFIG_DEST" ]; then
        cp -r "$REPO_ROOT/MacShell" "$CONFIG_DEST"
    fi
    touch "$HOME/.config/macshell/.setup_completed"
    touch "$CONFIG_DEST/.setup_completed"
    
    # Run setup worker
    if [ -f "$REPO_ROOT/MacShell/scripts/setup_assistant_worker.py" ]; then
        python3 "$REPO_ROOT/MacShell/scripts/setup_assistant_worker.py" run_setup '{"siri":false,"sound_pack":true,"wifi_manager":true}'
    fi
    log_ok "Installation completed in CLI mode. Launch with: quickshell -c MacShell"
    exit 0
fi

SETUP_QML="$REPO_ROOT/MacShell/SetupAssistant.qml"
if [ ! -f "$SETUP_QML" ]; then
    log_err "Could not find $SETUP_QML."
    exit 1
fi

log_ok "Bootstrap ready. Launching macOS Setup Assistant..."
echo -e "\n  ${CYAN}✨ Opening macOS Setup Assistant on your screen...${NC}\n"

# Run quickshell pointing to SetupAssistant.qml
quickshell -p "$SETUP_QML"
