#!/usr/bin/env bash
#
#  MacShell Bootstrap & Net-Installer
# One-line installer for MacShell on Arch Linux / Hyprland
#
# Usage:
#   sh -c "$(curl -fsSL https://raw.githubusercontent.com/4sakenme/MacOsSHell-New/main/bootstrap.sh)"
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
    echo -e "  ${BOLD} MacShell Net-Installer${NC} ${DIM}· macOS Tahoe / Sonoma Experience on Arch Linux${NC}"
    echo -e "  ${DIM}─────────────────────────────────────────────────────────────────${NC}\n"
}

banner

# ── 1. Environment Verification ──
log_info "Kiểm tra môi trường hệ thống..."

if [ "$(uname -s)" != "Linux" ]; then
    log_err "MacShell chỉ hỗ trợ hệ điều hành Linux."
    exit 1
fi

if ! command -v pacman >/dev/null 2>&1; then
    log_warn "Không phát hiện trình quản lý gói pacman (Arch Linux / CachyOS / EndeavourOS)."
    log_warn "MacShell được tối ưu hóa tốt nhất trên nền Arch Linux."
fi

if [ -z "${WAYLAND_DISPLAY:-}" ] && [ -z "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]; then
    log_warn "Hiện không phát hiện phiên Wayland/Hyprland đang hoạt động."
    log_warn "Bạn nên chạy trình cài đặt này bên trong phiên Hyprland để hiển thị giao diện kính mờ."
    echo -en "  ${AMBER}? Tiếp tục chạy bộ cài đặt? [y/N]: ${NC}"
    read -r ans
    if [[ ! "$ans" =~ ^[yY]$ ]]; then
        echo "Hủy cài đặt."
        exit 0
    fi
else
    log_ok "Đang chạy trên Wayland / Hyprland."
fi

# ── 2. Check & Install Essential Dependencies (git, quickshell) ──
log_info "Kiểm tra các gói tối thiểu bắt buộc..."

need_cmd() {
    command -v "$1" >/dev/null 2>&1
}

# Check git & curl
for pkg in git curl python3; do
    if need_cmd "$pkg"; then
        log_ok "$pkg đã sẵn sàng."
    else
        log_info "Đang cài đặt gói $pkg..."
        sudo pacman -S --needed --noconfirm "$pkg"
    fi
done

# Check Quickshell
if need_cmd quickshell || need_cmd qs; then
    log_ok "Quickshell đã được cài đặt ($(quickshell --version 2>/dev/null | head -n1 || echo 'ready'))."
else
    log_info "Quickshell chưa được cài đặt. Đang tìm trình cài đặt AUR..."
    AUR_HELPER=""
    if need_cmd yay; then
        AUR_HELPER="yay"
    elif need_cmd paru; then
        AUR_HELPER="paru"
    fi

    if [ -n "$AUR_HELPER" ]; then
        log_info "Cài đặt quickshell-git qua $AUR_HELPER..."
        $AUR_HELPER -S --needed --noconfirm quickshell-git
    else
        log_warn "Không tìm thấy yay hoặc paru. Đang tự động cài đặt yay-bin..."
        TMP_YAY=$(mktemp -d)
        git clone --depth 1 https://aur.archlinux.org/yay-bin.git "$TMP_YAY"
        (cd "$TMP_YAY" && makepkg -si --noconfirm)
        rm -rf "$TMP_YAY"
        yay -S --needed --noconfirm quickshell-git
    fi
fi

# ── 3. Prepare Temporary Bootstrap Directory ──
BOOTSTRAP_DIR="$HOME/.cache/macshell-bootstrap"
REPO_URL="https://github.com/4sakenme/MacOsSHell-New.git"

log_info "Chuẩn bị tài nguyên Setup Assistant..."
mkdir -p "$BOOTSTRAP_DIR"

# If running inside existing local clone, sync directly for instant speed
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
if [ -f "$SCRIPT_DIR/MacShell/SetupAssistant.qml" ]; then
    log_info "Phát hiện mã nguồn cục bộ tại $SCRIPT_DIR, tạo liên kết..."
    mkdir -p "$BOOTSTRAP_DIR/repo"
    cp -ru "$SCRIPT_DIR"/* "$BOOTSTRAP_DIR/repo/" 2>/dev/null || true
else
    if [ -d "$BOOTSTRAP_DIR/repo/.git" ]; then
        log_info "Cập nhật tài nguyên Setup Assistant từ GitHub..."
        git -C "$BOOTSTRAP_DIR/repo" fetch --depth 1 origin main || true
        git -C "$BOOTSTRAP_DIR/repo" reset --hard origin/main || true
    else
        log_info "Đang tải giao diện Setup Assistant từ GitHub..."
        rm -rf "$BOOTSTRAP_DIR/repo"
        git clone --depth 1 "$REPO_URL" "$BOOTSTRAP_DIR/repo"
    fi
fi

SETUP_QML="$BOOTSTRAP_DIR/repo/MacShell/SetupAssistant.qml"
if [ ! -f "$SETUP_QML" ]; then
    log_err "Không tìm thấy $SETUP_QML."
    exit 1
fi

# ── 4. Launch Setup Assistant OOBE ──
log_ok "Tài nguyên đã sẵn sàng. Khởi chạy macOS Setup Assistant..."
echo -e "\n  ${CYAN}✨ Đang mở giao diện macOS Setup Assistant trên màn hình của bạn...${NC}\n"

# Run quickshell pointing to the standalone SetupAssistant.qml
quickshell -p "$SETUP_QML"
