#!/usr/bin/env python3
"""
macshell-upstream-sync.py
Automatically fetches, merges, and adapts updates from upstream (0-ss/MacShell)
into the user's customized fork (4sakenme/MacOsSHell-New) without losing custom
features (Siri/Gemini, AirDrop, Custom Widgets, Liquid Waterflow Shader, Settings UI).
Automatically commits and pushes to GitHub (origin main).
"""

import os
import sys
import json
import shutil
import urllib.request
import subprocess

PROTECTED_PATHS = [
    "modules/TypeToSiri.qml",
    "modules/SiriOrb.qml",
    "modules/SiriEdgeGlow.qml",
    "modules/AppleIntelligenceSettings.qml",
    "modules/GenieAnimation.qml",
    "modules/flowingborder.frag",
    "modules/flowingborder.frag.qsb",
    "modules/siriorb.frag",
    "modules/siriorb.frag.qsb",
    "modules/siriedgeglow.frag",
    "modules/siriedgeglow.frag.qsb",
    "AirDrop.qml",
    "BatteryWidget.qml",
    "GifWidget.qml",
    "Reminders.qml",
    "RemindersWidget.qml",
    "StocksWidget.qml",
    "SystemMonitorWidget.qml",
    "assets/waterflow.frag",
    "assets/MacOS_26_icon.webp",
    "assets/macshell-auto-update.sh",
    "assets/macshell-upstream-sync.py",
    "scripts/siri_daemon.py",
    "scripts/awake_siri.sh",
    "scripts/macshell-airdrop.py",
    "scripts/macshell-ap.sh",
    "scripts/setup_assistant_worker.py",
    "gemini_config.json",
    "siri_settings.json",
    "waterflow.frag.qsb",
    "modules/waterflow.frag.qsb",
]

def run(cmd, cwd=None, check=False):
    res = subprocess.run(cmd, cwd=cwd, shell=isinstance(cmd, str), capture_output=True, text=True)
    if check and res.returncode != 0:
        raise RuntimeError(f"Command failed ({res.returncode}): {cmd}\n{res.stderr}")
    return res

def get_latest_upstream_tag():
    try:
        req = urllib.request.Request(
            "https://api.github.com/repos/0-ss/MacShell/releases/latest",
            headers={"User-Agent": "MacShell-AutoSync"}
        )
        with urllib.request.urlopen(req, timeout=10) as resp:
            data = json.loads(resp.read().decode())
            return data.get("tag_name", "").strip() or "0.5.1"
    except Exception:
        return "0.5.1"

def sync_git_repo(repo_dir):
    print(f"[*] Inspecting local git repo at {repo_dir}...")
    
    # 1. Ensure remotes exist
    run("git remote add upstream https://github.com/0-ss/MacShell.git", cwd=repo_dir)
    run("git fetch upstream main --tags", cwd=repo_dir)
    run("git fetch origin main", cwd=repo_dir)

    # 2. Check if upstream has new commits
    rev_upstream = run("git rev-parse upstream/main", cwd=repo_dir).stdout.strip()
    rev_head = run("git rev-parse HEAD", cwd=repo_dir).stdout.strip()
    merge_base = run("git merge-base HEAD upstream/main", cwd=repo_dir).stdout.strip()

    print(f"[*] Upstream SHA: {rev_upstream[:7]} | HEAD SHA: {rev_head[:7]}")

    tag = get_latest_upstream_tag()

    # 3. List files changed between merge_base and upstream/main
    diff_files = run(f"git diff --name-only {merge_base} upstream/main", cwd=repo_dir).stdout.strip().splitlines()
    diff_files = [f.strip() for f in diff_files if f.strip()]

    if not diff_files:
        print("[*] Already fully up to date with upstream 0-ss/MacShell.")
        return False, tag

    print(f"[*] Upstream modified {len(diff_files)} files: {', '.join(diff_files[:5])}...")

    # 4. Ingest new files and non-conflicting modifications
    updated_count = 0
    for f in diff_files:
        # Never overwrite strictly protected custom files
        rel_f = f.replace("MacShell/", "") if f.startswith("MacShell/") else f
        if any(rel_f.endswith(p) or p.endswith(rel_f) for p in PROTECTED_PATHS):
            print(f"    - Skipping protected custom file: {f}")
            continue

        # Check if file is completely new in upstream
        local_path = os.path.join(repo_dir, f)
        if not os.path.exists(local_path):
            print(f"    + Adding new upstream file: {f}")
            run(f"git checkout upstream/main -- '{f}'", cwd=repo_dir)
            updated_count += 1
            continue

        # For existing core files (MacDock.qml, MacBar.qml, Desktop.qml, etc.):
        # Try a safe merge-file or checkout if local matches merge_base
        local_diff = run(f"git diff {merge_base} HEAD -- '{f}'", cwd=repo_dir).stdout.strip()
        if not local_diff:
            # We haven't modified this file locally, safe to update directly to upstream!
            print(f"    ~ Updating clean file to upstream: {f}")
            run(f"git checkout upstream/main -- '{f}'", cwd=repo_dir)
            updated_count += 1
        else:
            # Both sides modified it: attempt 3-way merge-file
            print(f"    * Merging changes into customized file: {f}")
            base_blob = run(f"git show {merge_base}:'{f}'", cwd=repo_dir).stdout
            upstream_blob = run(f"git show upstream/main:'{f}'", cwd=repo_dir).stdout
            
            base_tmp = f"/tmp/base_{os.path.basename(f)}"
            upstream_tmp = f"/tmp/up_{os.path.basename(f)}"
            with open(base_tmp, "w") as tf: tf.write(base_blob)
            with open(upstream_tmp, "w") as tf: tf.write(upstream_blob)

            # git merge-file <current> <base> <other>
            # -Xours gives precedence to our custom logic if conflicts arise
            merge_res = run(["git", "merge-file", "-Xours", local_path, base_tmp, upstream_tmp], cwd=repo_dir)
            if merge_res.returncode == 0:
                print(f"      Merged cleanly: {f}")
                updated_count += 1
            else:
                print(f"      Merged with conflict resolution (ours prioritized): {f}")
                # Remove any stray conflict markers if any
                clean_conflict_markers(local_path)
                updated_count += 1

            for tmpf in [base_tmp, upstream_tmp]:
                if os.path.exists(tmpf): os.remove(tmpf)

    # 5. Recompile any updated shaders
    qsb_bin = shutil.which("qsb") or ("/usr/lib/qt6/bin/qsb" if os.path.exists("/usr/lib/qt6/bin/qsb") else "")
    if qsb_bin:
        for root_dir, _, files in os.walk(os.path.join(repo_dir, "MacShell")):
            for fn in files:
                if fn.endswith((".frag", ".vert")):
                    sh_path = os.path.join(root_dir, fn)
                    out_path = sh_path + ".qsb"
                    run([qsb_bin, "--glsl", "300es,120", "--hlsl", "50", "--msl", "12", "-o", out_path, sh_path])

    # 6. Check git status and commit & push if modified
    st = run("git status --porcelain", cwd=repo_dir).stdout.strip()
    if st:
        print("[*] Changes detected, creating git commit and pushing...")
        run("git add -A", cwd=repo_dir)
        commit_msg = f"sync(upstream): auto-ingest updates from 0-ss/MacShell {tag}"
        run(["git", "commit", "-m", commit_msg], cwd=repo_dir)
        
        # Auto-push to origin main and feature/custom-widgets
        push_res = run("git push origin main", cwd=repo_dir)
        if push_res.returncode == 0:
            print("[+] Successfully auto-pushed updates to origin main!")
            run("git push origin main:feature/custom-widgets", cwd=repo_dir)
        else:
            print(f"[!] Push warning: {push_res.stderr}")
        return True, tag
    else:
        print("[*] No code changes needed to commit.")
        return False, tag

def clean_conflict_markers(file_path):
    if not os.path.exists(file_path): return
    with open(file_path, "r", encoding="utf-8", errors="ignore") as f:
        lines = f.readlines()
    
    out = []
    in_theirs = False
    for line in lines:
        if line.startswith("<<<<<<<"):
            continue
        elif line.startswith("======="):
            in_theirs = True
            continue
        elif line.startswith(">>>>>>>"):
            in_theirs = False
            continue
        if not in_theirs:
            out.append(line)

    with open(file_path, "w", encoding="utf-8") as f:
        f.writelines(out)

def main():
    repo_dir = os.path.expanduser("~/MacShell")
    dest_dir = os.path.expanduser("~/.config/quickshell/MacShell")

    changed = False
    tag = "0.5.1"

    if os.path.exists(os.path.join(repo_dir, ".git")):
        changed, tag = sync_git_repo(repo_dir)
    else:
        print("[!] No local git clone at ~/MacShell, checking online archives...")

    # Always ensure destination ~/.config/quickshell/MacShell is up to date
    if os.path.exists(os.path.join(repo_dir, "MacShell")):
        print(f"[*] Syncing to Quickshell config directory ({dest_dir})...")
        run(f"rsync -av --exclude='.git' '{repo_dir}/MacShell/' '{dest_dir}/'")

    # Record state
    state_file = os.path.expanduser("~/.local/share/macshell/state.env")
    if os.path.exists(state_file):
        sha = run(f"git -C '{repo_dir}' rev-parse HEAD").stdout.strip() if os.path.exists(os.path.join(repo_dir, ".git")) else "latest"
        run(f"sed -i 's/^installed_commit=.*/installed_commit={sha}/' '{state_file}'")
        run(f"sed -i 's/^installed=.*/installed={tag}/' '{state_file}'")

    print("[+] Upstream auto-sync completed successfully!")

if __name__ == "__main__":
    main()
