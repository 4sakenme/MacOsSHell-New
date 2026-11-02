#!/usr/bin/env bash
# macshell-auto-update.sh: Checks and applies updates for MacShell from 4sakenme/MacOsSHell-New
set -uo pipefail

REPO="${MACSHELL_REPO:-4sakenme/MacOsSHell-New}"
BRANCH="${MACSHELL_BRANCH:-main}"
CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
STATE_DIR="$DATA_HOME/macshell"
STATE_FILE="$STATE_DIR/state.env"
BACKUP_DIR="$STATE_DIR/backups"
DEST="${MACSHELL_DEST:-$CONFIG_HOME/quickshell/MacShell}"
LOCK_DEST="${MACSHELL_LOCK_DEST:-$CONFIG_HOME/quickshell/MacLock}"

mkdir -p "$STATE_DIR" "$BACKUP_DIR"

state_get() { [ -f "$STATE_FILE" ] && sed -n "s/^$1=//p" "$STATE_FILE" | head -n1; }
state_set() {
    local k="$1" v="$2"
    if [ -f "$STATE_FILE" ] && grep -q "^$k=" "$STATE_FILE"; then
        sed -i "s|^$k=.*|$k=$v|" "$STATE_FILE"
    else
        echo "$k=$v" >> "$STATE_FILE"
    fi
}

# Current installed version & commit
get_current_version() {
    local v=""
    [ -f "$DEST/VERSION" ] && v=$(head -n1 "$DEST/VERSION" | tr -d '[:space:]')
    [ -z "$v" ] && v=$(state_get installed)
    printf '%s' "${v:-0.4.9}"
}

get_current_commit() {
    local c=""
    c=$(state_get installed_commit)
    if [ -z "$c" ] && [ -d "$HOME/MacShell/.git" ]; then
        c=$(git -C "$HOME/MacShell" rev-parse HEAD 2>/dev/null || true)
    fi
    printf '%s' "${c:-unknown}"
}

clean_str() { printf '%s' "$1" | tr -d '"\\\n\r' | cut -c1-200; }

cmd_check() {
    local cur_ver cur_sha remote_sha remote_ver msg date url status
    cur_ver=$(get_current_version)
    cur_sha=$(get_current_commit)
    url="https://github.com/$REPO"

    # 1. Query remote commit SHA
    remote_sha=$(git ls-remote "https://github.com/$REPO.git" "refs/heads/$BRANCH" 2>/dev/null | awk '{print $1}')
    if [ -z "$remote_sha" ]; then
        remote_sha=$(curl -fsSL --max-time 10 -H "Accept: application/vnd.github.sha" "https://api.github.com/repos/$REPO/commits/$BRANCH" 2>/dev/null || true)
    fi

    if [ -z "$remote_sha" ]; then
        printf '{"status":"error","message":"Cannot connect to repository %s"}\n' "$REPO"
        return 1
    fi

    # 2. Query remote details & commit message
    msg=""
    date=""
    remote_ver="$cur_ver"
    local json_info
    json_info=$(curl -fsSL --max-time 10 "https://api.github.com/repos/$REPO/commits/$BRANCH" 2>/dev/null || true)
    if [ -n "$json_info" ]; then
        msg=$(printf '%s' "$json_info" | jq -r '.commit.message // ""' 2>/dev/null | head -n1 || true)
        date=$(printf '%s' "$json_info" | jq -r '.commit.committer.date // ""' 2>/dev/null || true)
    fi
    [ -z "$msg" ] && msg="Latest changes on $BRANCH"

    # Try fetching remote VERSION
    local r_ver
    r_ver=$(curl -fsSL --max-time 5 "https://raw.githubusercontent.com/$REPO/$BRANCH/MacShell/VERSION" 2>/dev/null | head -n1 | tr -d '[:space:]')
    [ -n "$r_ver" ] && remote_ver="$r_ver"

    # Compare
    local short_cur short_rem
    short_cur="${cur_sha:0:7}"
    short_rem="${remote_sha:0:7}"

    if [ "$cur_sha" = "$remote_sha" ] || [ "$short_cur" = "$short_rem" ]; then
        status="uptodate"
    else
        status="available"
    fi

    printf '{"status":"%s","repo":"%s","branch":"%s","current_version":"%s","latest_version":"%s","current_commit":"%s","latest_commit":"%s","commit_message":"%s","commit_date":"%s","url":"%s"}\n' \
        "$status" "$REPO" "$BRANCH" "$(clean_str "$cur_ver")" "$(clean_str "$remote_ver")" "$short_cur" "$short_rem" "$(clean_str "$msg")" "$(clean_str "$date")" "$url"
    return 0
}

cmd_apply() {
    echo "PROGRESS:5:Connecting to GitHub repository $REPO..."
    local cur_ver cur_sha
    cur_ver=$(get_current_version)
    cur_sha=$(get_current_commit)

    local tmp_dir
    tmp_dir=$(mktemp -d /tmp/macshell-update.XXXXXX)
    # shellcheck disable=SC2064
    trap "rm -rf '$tmp_dir'" EXIT INT TERM

    echo "PROGRESS:20:Downloading latest update package from GitHub..."
    local tarball="$tmp_dir/update.tar.gz"
    if ! curl -fsSL --retry 2 --max-time 120 "https://github.com/$REPO/archive/refs/heads/$BRANCH.tar.gz" -o "$tarball"; then
        echo "PROGRESS:100:Error: Failed to download update from GitHub." >&2
        return 1
    fi

    echo "PROGRESS:45:Extracting and verifying package contents..."
    mkdir -p "$tmp_dir/src"
    if ! tar -xzf "$tarball" --strip-components=1 -C "$tmp_dir/src"; then
        echo "PROGRESS:100:Error: Corrupted archive or extraction failed." >&2
        return 1
    fi

    if [ ! -d "$tmp_dir/src/MacShell" ]; then
        echo "PROGRESS:100:Error: Invalid MacShell directory structure." >&2
        return 1
    fi

    local ts
    ts=$(date +%Y%m%d_%H%M%S)
    local cur_backup="$BACKUP_DIR/$ts"
    echo "PROGRESS:60:Creating backup at $cur_backup..."
    mkdir -p "$cur_backup"
    [ -d "$DEST" ] && cp -a "$DEST" "$cur_backup/MacShell"
    [ -d "$LOCK_DEST" ] && cp -a "$LOCK_DEST" "$cur_backup/MacLock"

    echo "PROGRESS:75:Installing updated MacShell components..."
    mkdir -p "$DEST"
    rsync -a --delete \
        --exclude='.git' \
        --exclude='__pycache__' \
        --exclude='state.env' \
        --exclude='gemini_config.json' \
        --exclude='siri_settings.json' \
        "$tmp_dir/src/MacShell/" "$DEST/"

    if [ -d "$tmp_dir/src/MacLock" ]; then
        mkdir -p "$LOCK_DEST"
        rsync -a --delete \
            --exclude='.git' \
            --exclude='__pycache__' \
            "$tmp_dir/src/MacLock/" "$LOCK_DEST/"
    fi

    # Also keep git repo in sync if user has local clone
    if [ -d "$HOME/MacShell/.git" ]; then
        echo "PROGRESS:85:Syncing local git workspace..."
        git -C "$HOME/MacShell" fetch origin "$BRANCH" 2>/dev/null || true
        git -C "$HOME/MacShell" checkout "$BRANCH" 2>/dev/null || true
        git -C "$HOME/MacShell" pull --ff-only origin "$BRANCH" 2>/dev/null || true
    fi

    # Compile shaders if qsb exists
    if command -v qsb >/dev/null 2>&1; then
        echo "PROGRESS:90:Compiling graphics shaders (qsb)..."
        for sh in "$DEST"/*.frag "$DEST"/*.vert; do
            [ -f "$sh" ] || continue
            qsb --glsl "300es,120" --hlsl 50 --msl 12 -o "$sh.qsb" "$sh" 2>/dev/null || true
        done
        for sh in "$LOCK_DEST"/*.frag "$LOCK_DEST"/*.vert; do
            [ -f "$sh" ] || continue
            qsb --glsl "300es,120" --hlsl 50 --msl 12 -o "$sh.qsb" "$sh" 2>/dev/null || true
        done
    fi

    # Record updated state
    local new_sha new_ver
    new_sha=$(git ls-remote "https://github.com/$REPO.git" "refs/heads/$BRANCH" 2>/dev/null | awk '{print $1}')
    [ -z "$new_sha" ] && new_sha="latest"
    new_ver=$(get_current_version)

    state_set "repo" "$REPO"
    state_set "branch" "$BRANCH"
    state_set "installed" "$new_ver"
    state_set "installed_commit" "$new_sha"
    state_set "installed_at" "$(date -u +%Y-%m-%dT%H:%M:%SZ)"

    echo "PROGRESS:98:Reloading MacShell environment..."
    touch "$DEST/shell.qml"
    [ -d "$LOCK_DEST" ] && touch "$LOCK_DEST/shell.qml"

    echo "PROGRESS:100:Update completed successfully! MacShell has been updated."
    return 0
}

case "${1:-check}" in
    check) cmd_check ;;
    apply) cmd_apply ;;
    *) echo "Usage: $0 {check|apply}" >&2; exit 1 ;;
esac
