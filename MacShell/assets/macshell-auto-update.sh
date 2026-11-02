#!/usr/bin/env bash
# macshell-auto-update.sh: Checks and applies updates for MacShell from 0-ss/MacShell & 4sakenme/MacOsSHell-New
set -uo pipefail

REPO="${MACSHELL_REPO:-4sakenme/MacOsSHell-New}"
UPSTREAM_REPO="0-ss/MacShell"
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

get_current_version() {
    local v=""
    [ -f "$DEST/VERSION" ] && v=$(head -n1 "$DEST/VERSION" | tr -d '[:space:]')
    [ -z "$v" ] && v=$(state_get installed)
    printf '%s' "${v:-0.5.1}"
}

get_current_commit() {
    local c=""
    c=$(state_get installed_commit)
    if [ -z "$c" ] && [ -d "$HOME/MacShell/.git" ]; then
        c=$(git -C "$HOME/MacShell" rev-parse HEAD 2>/dev/null || true)
    fi
    printf '%s' "${c:-unknown}"
}

clean_str() { printf '%s' "$1" | tr -d '"\\\n\r' | cut -c1-300; }

cmd_check() {
    local cur_ver cur_sha remote_sha remote_ver rel_title rel_body msg date url status
    cur_ver=$(get_current_version)
    cur_sha=$(get_current_commit)
    url="https://github.com/$REPO"

    # 1. Check latest release tag and body from upstream 0-ss/MacShell
    local upstream_json
    upstream_json=$(curl -fsSL --max-time 8 "https://api.github.com/repos/$UPSTREAM_REPO/releases/latest" 2>/dev/null || true)
    
    local up_tag up_name up_body
    up_tag=$(printf '%s' "$upstream_json" | jq -r '.tag_name // ""' 2>/dev/null || true)
    up_name=$(printf '%s' "$upstream_json" | jq -r '.name // ""' 2>/dev/null || true)
    up_body=$(printf '%s' "$upstream_json" | jq -r '.body // ""' 2>/dev/null || true)
    
    # 2. Check latest commit from 4sakenme/MacOsSHell-New
    remote_sha=$(git ls-remote "https://github.com/$REPO.git" "refs/heads/$BRANCH" 2>/dev/null | awk '{print $1}')
    if [ -z "$remote_sha" ]; then
        remote_sha=$(curl -fsSL --max-time 8 -H "Accept: application/vnd.github.sha" "https://api.github.com/repos/$REPO/commits/$BRANCH" 2>/dev/null || true)
    fi

    # 3. Clean up release notes
    local clean_notes
    clean_notes=$(python3 -c "
import sys, re
body = sys.stdin.read()
body = re.sub(r'<[^>]+>', '', body)
body = re.sub(r'#+\s*', '', body)
body = re.sub(r'\r', '', body).strip()
lines = [l.strip() for l in body.split('\n') if l.strip()]
print(' • '.join(lines[:6]))
" <<< "$up_body" 2>/dev/null || true)

    [ -z "$clean_notes" ] && clean_notes="Desktop Quick Look, Customizable Folders, Apps Dock Launcher & Right Click improvements."

    # Commit message from fork
    msg=""
    date=""
    local json_info
    json_info=$(curl -fsSL --max-time 8 "https://api.github.com/repos/$REPO/commits/$BRANCH" 2>/dev/null || true)
    if [ -n "$json_info" ]; then
        msg=$(printf '%s' "$json_info" | jq -r '.commit.message // ""' 2>/dev/null | head -n1 || true)
        date=$(printf '%s' "$json_info" | jq -r '.commit.committer.date // ""' 2>/dev/null || true)
    fi
    [ -z "$msg" ] && msg="Latest updates from $BRANCH"

    # Determine version and status
    remote_ver="${up_tag:-$cur_ver}"
    local short_cur short_rem
    short_cur="${cur_sha:0:7}"
    short_rem="${remote_sha:0:7}"

    # Version comparison: does up_tag > cur_ver?
    local cmp
    cmp=$(printf '%s\n%s\n' "$cur_ver" "$remote_ver" | sort -V | tail -n1)
    if [ "$remote_ver" != "$cur_ver" ] && [ "$cmp" = "$remote_ver" ]; then
        status="available"
    elif [ -n "$remote_sha" ] && [ "$cur_sha" != "$remote_sha" ] && [ "$short_cur" != "$short_rem" ]; then
        status="available"
    else
        status="uptodate"
    fi

    if [ "$status" = "available" ]; then
        # Notify user of new update
        notify-send -i "$DEST/assets/MacOS_26_icon.webp" "MacShell Software Update" "MacShell $remote_ver is available!\n$clean_notes" 2>/dev/null || true
    fi

    printf '{"status":"%s","repo":"%s","upstream_repo":"%s","branch":"%s","current_version":"%s","latest_version":"%s","release_title":"%s","release_notes":"%s","current_commit":"%s","latest_commit":"%s","commit_message":"%s","commit_date":"%s","url":"%s"}\n' \
        "$status" "$REPO" "$UPSTREAM_REPO" "$BRANCH" "$(clean_str "$cur_ver")" "$(clean_str "$remote_ver")" "$(clean_str "${up_name:-MacShell $remote_ver}")" "$(clean_str "$clean_notes")" "$short_cur" "$short_rem" "$(clean_str "$msg")" "$(clean_str "$date")" "$url"
    return 0
}

cmd_apply() {
    echo "PROGRESS:5:Connecting to repositories (0-ss/MacShell & 4sakenme/MacOsSHell-New)..."
    local cur_ver cur_sha
    cur_ver=$(get_current_version)
    cur_sha=$(get_current_commit)

    # 1. Smart Upstream Ingest & Auto-Push Engine:
    # Automatically pulls new changes from 0-ss/MacShell, merges them into our fork,
    # protects custom features, and automatically pushes to GitHub (4sakenme/MacOsSHell-New)!
    local sync_script=""
    [ -f "$DEST/assets/macshell-upstream-sync.py" ] && sync_script="$DEST/assets/macshell-upstream-sync.py"
    [ -z "$sync_script" ] && [ -f "$HOME/MacShell/MacShell/assets/macshell-upstream-sync.py" ] && sync_script="$HOME/MacShell/MacShell/assets/macshell-upstream-sync.py"

    if [ -n "$sync_script" ]; then
        echo "PROGRESS:15:Auto-ingesting upstream updates from 0-ss/MacShell..."
        python3 "$sync_script" 2>&1 | while read -r line; do echo "PROGRESS:25:$line"; done || true
    fi

    local tmp_dir
    tmp_dir=$(mktemp -d /tmp/macshell-update.XXXXXX)
    # shellcheck disable=SC2064
    trap "rm -rf '$tmp_dir'" EXIT INT TERM

    echo "PROGRESS:30:Downloading update package..."
    local tarball="$tmp_dir/update.tar.gz"
    if ! curl -fsSL --retry 2 --max-time 120 "https://github.com/$REPO/archive/refs/heads/$BRANCH.tar.gz" -o "$tarball"; then
        # Fallback to local clone if available
        if [ -d "$HOME/MacShell/MacShell" ]; then
            echo "PROGRESS:35:Using local updated git repository..."
            mkdir -p "$tmp_dir/src"
            cp -a "$HOME/MacShell/." "$tmp_dir/src/"
        else
            echo "PROGRESS:100:Error: Failed to download update from GitHub." >&2
            return 1
        fi
    else
        echo "PROGRESS:45:Extracting and verifying package contents..."
        mkdir -p "$tmp_dir/src"
        tar -xzf "$tarball" --strip-components=1 -C "$tmp_dir/src" || true
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

    # Compile shaders if qsb exists (checking PATH and /usr/lib/qt6/bin/qsb)
    local qsb_cmd=""
    if command -v qsb >/dev/null 2>&1; then
        qsb_cmd="qsb"
    elif [ -x /usr/lib/qt6/bin/qsb ]; then
        qsb_cmd="/usr/lib/qt6/bin/qsb"
    fi

    if [ -n "$qsb_cmd" ]; then
        echo "PROGRESS:90:Compiling graphics shaders ($qsb_cmd)..."
        for sh in "$DEST"/*.frag "$DEST"/*.vert "$DEST"/modules/*.frag; do
            [ -f "$sh" ] || continue
            "$qsb_cmd" --glsl "300es,120" --hlsl 50 --msl 12 -o "$sh.qsb" "$sh" 2>/dev/null || true
        done
        for sh in "$LOCK_DEST"/*.frag "$LOCK_DEST"/*.vert; do
            [ -f "$sh" ] || continue
            "$qsb_cmd" --glsl "300es,120" --hlsl 50 --msl 12 -o "$sh.qsb" "$sh" 2>/dev/null || true
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

    echo "PROGRESS:97:Setting up macOS Welcome experience..."
    cat <<EOF > "$STATE_DIR/pending_welcome"
{"version":"$new_ver","title":"${up_name:-MacShell $new_ver}","notes":"$clean_notes"}
EOF

    echo "PROGRESS:100:Restarting MacShell to apply updates..."
    # Launch clean Quickshell reload in background
    setsid sh -c "sleep 0.8; pkill -f 'qs -c MacShell' 2>/dev/null || pkill -f 'quickshell -c MacShell' 2>/dev/null; sleep 0.3; LC_ALL=C.UTF-8 qs -c MacShell &" >/dev/null 2>&1 &
    return 0
}

case "${1:-check}" in
    check) cmd_check ;;
    apply) cmd_apply ;;
    *) echo "Usage: $0 {check|apply}" >&2; exit 1 ;;
esac
