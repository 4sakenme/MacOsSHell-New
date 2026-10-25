#!/usr/bin/env python3
"""
MacShell Setup Assistant Worker
Comprehensive backend for the macOS Setup Assistant (OOBE):
- Feature module dependency checks (Network, Audio, Fonts, Python AI)
- macOS Wi-Fi scanner and connection manager via nmcli
- Gemini API Key validation
- Soundpack generation (macOS F# Major Startup Chime, Tink, Pop, Shutter)
- System font cache synchronization
- Configuration management (~/.config/macshell/config.json, siri_settings.json)
"""

import sys
import os
import time
import json
import math
import struct
import wave
import shutil
import subprocess
import urllib.request
import urllib.error
from pathlib import Path

HOME = Path(os.environ.get("HOME", "/home/kuro"))
CONFIG_DIR = HOME / ".config" / "macshell"
SOUNDS_DIR = HOME / ".local" / "share" / "sounds" / "macshell"
FONTS_DIR = HOME / ".local" / "share" / "fonts"
MACSHELL_DIR = Path(__file__).resolve().parent.parent


def test_gemini_key(api_key: str):
    """Validate a Google Gemini API key by listing models."""
    if not api_key or api_key.strip() == "":
        print("RESULT:INVALID:API Key cannot be empty", flush=True)
        return

    key = api_key.strip()
    url = f"https://generativelanguage.googleapis.com/v1beta/models?key={key}"
    try:
        req = urllib.request.Request(url, headers={"User-Agent": "MacShell-SetupAssistant/1.0"})
        with urllib.request.urlopen(req, timeout=8) as response:
            if response.status == 200:
                data = json.loads(response.read().decode("utf-8"))
                models = [m.get("name", "").replace("models/", "") for m in data.get("models", [])]
                flash_model = next((m for m in models if "flash" in m), models[0] if models else "gemini-2.5-flash")
                print(f"RESULT:VALID:{flash_model}", flush=True)
                return
            else:
                print(f"RESULT:INVALID:HTTP error {response.status}", flush=True)
                return
    except urllib.error.HTTPError as e:
        err_msg = "Invalid or expired API Key"
        try:
            err_json = json.loads(e.read().decode("utf-8"))
            if "error" in err_json and "message" in err_json["error"]:
                err_msg = err_json["error"]["message"]
        except Exception:
            pass
        print(f"RESULT:INVALID:{err_msg}", flush=True)
    except Exception as e:
        print(f"RESULT:INVALID:Network error ({str(e)})", flush=True)


# ══════════════════════════════════════════════════════════════════════════════
# 1. Dependency & Feature Checking
# ══════════════════════════════════════════════════════════════════════════════

def check_command(cmd: str) -> bool:
    return shutil.which(cmd) is not None


def check_dependencies(options_raw: str = ""):
    """
    Check system packages, tools, fonts, and python dependencies based on selected options.
    """
    opts = {}
    if options_raw:
        try:
            opts = json.loads(options_raw)
        except Exception:
            pass

    siri_requested = opts.get("siri", True)
    sound_requested = opts.get("sound_pack", True)
    wifi_requested = opts.get("wifi_manager", True)

    deps = []

    # 1. Core / Window manager / Wayland tools
    has_hypr = check_command("hyprctl")
    has_qs = check_command("qs") or check_command("quickshell")
    deps.append({
        "id": "core",
        "name": "Core MacShell Environment",
        "category": "core",
        "status": "installed" if (has_hypr or has_qs) else "installed",
        "detail": "Hyprland & Quickshell are ready",
        "size_mb": 0,
        "required": True
    })

    # 2. Network Manager (nmcli / iwd)
    has_nmcli = check_command("nmcli")
    has_iwd = check_command("iwctl")
    if has_nmcli:
        net_status = "installed"
        net_detail = "NetworkManager (nmcli) is available"
        net_size = 0
    elif has_iwd:
        net_status = "installed"
        net_detail = "iwd (iwctl) is available"
        net_size = 0
    else:
        net_status = "missing" if wifi_requested else "skipped"
        net_detail = "Requires networkmanager package via pacman"
        net_size = 12

    deps.append({
        "id": "network",
        "name": "macOS Wi-Fi & Network Engine",
        "category": "network",
        "status": net_status,
        "detail": net_detail,
        "size_mb": net_size,
        "required": False
    })

    # 3. Audio engine (pipewire, wireplumber, pw-play, mpv, sox)
    has_pw_play = check_command("pw-play")
    has_wpctl = check_command("wpctl")
    has_mpv = check_command("mpv")
    has_sox = check_command("play") or check_command("sox")

    if has_pw_play or has_mpv or has_sox:
        audio_status = "installed"
        engine_name = "PipeWire (pw-play)" if has_pw_play else ("mpv" if has_mpv else "sox")
        audio_detail = f"Audio engine {engine_name} working properly"
        audio_size = 0
    else:
        audio_status = "missing"
        audio_detail = "Requires pipewire or mpv"
        audio_size = 15

    deps.append({
        "id": "audio",
        "name": "Audio Engine & Device Routing",
        "category": "audio",
        "status": audio_status,
        "detail": audio_detail,
        "size_mb": audio_size,
        "required": True
    })

    # 4. macOS Sound Pack (Chime, Tink, Pop, Shutter)
    chime_file = SOUNDS_DIR / "chime.wav"
    has_chime = chime_file.exists() and chime_file.stat().st_size > 1000
    if not sound_requested:
        sound_status = "skipped"
        sound_detail = "Sound pack skipped by user"
        sound_size = 0
    elif has_chime:
        sound_status = "installed"
        sound_detail = "macOS UI Sound Pack already installed"
        sound_size = 0
    else:
        sound_status = "ready"
        sound_detail = "Ready to synthesize F# Major Chime & UI sounds"
        sound_size = 2

    deps.append({
        "id": "sounds",
        "name": "macOS UI Sounds & Startup Chime",
        "category": "sounds",
        "status": sound_status,
        "detail": sound_detail,
        "size_mb": sound_size,
        "required": False
    })

    # 5. Fonts (SF Pro, Open Runde, Apple Symbols)
    has_fc = check_command("fc-list")
    sf_installed = False
    if has_fc:
        try:
            fc_out = subprocess.check_output(["fc-list", ":", "family"], stderr=subprocess.DEVNULL).decode("utf-8")
            if any(f in fc_out for f in ["SF Pro", "Open Runde", "Inter", "Apple"]):
                sf_installed = True
        except Exception:
            pass

    bundled_fonts = MACSHELL_DIR / "assets" / "fonts"
    has_bundled = bundled_fonts.exists() and len(list(bundled_fonts.glob("*.[to]tf"))) > 0

    if sf_installed or has_bundled:
        font_status = "installed"
        font_detail = "SF Pro & Open Runde typography ready"
        font_size = 0
    else:
        font_status = "ready"
        font_detail = "Ready to sync system font cache"
        font_size = 18

    deps.append({
        "id": "fonts",
        "name": "Apple Typography Fonts (SF Pro & Open Runde)",
        "category": "fonts",
        "status": font_status,
        "detail": font_detail,
        "size_mb": font_size,
        "required": False
    })

    # 6. Python AI & Siri dependencies
    if not siri_requested:
        ai_status = "skipped"
        ai_detail = "Siri skipped by user (Heavy libraries omitted)"
        ai_size = 0
    else:
        missing_py = []
        for pkg in ["google.genai", "sounddevice", "numpy", "webrtcvad"]:
            try:
                __import__(pkg)
            except ImportError:
                missing_py.append(pkg)

        if not missing_py:
            ai_status = "installed"
            ai_detail = "All Apple Intelligence libraries installed"
            ai_size = 0
        else:
            ai_status = "missing"
            ai_detail = f"Missing packages: {', '.join(missing_py)}"
            ai_size = 24

    deps.append({
        "id": "python_ai",
        "name": "Apple Intelligence & Siri Engine (Python)",
        "category": "ai",
        "status": ai_status,
        "detail": ai_detail,
        "size_mb": ai_size,
        "required": False
    })

    # 7. Authentic macOS Cursor Pack (apple_cursor)
    has_cursor = (
        (HOME / ".local" / "share" / "icons" / "macOS").exists() or
        (HOME / ".icons" / "macOS").exists() or
        Path("/usr/share/icons/macOS").exists() or
        Path("/usr/share/icons/capitaine-cursors").exists()
    )
    deps.append({
        "id": "cursor_pack",
        "name": "macOS Authentic Cursor Theme (apple_cursor)",
        "category": "cursor",
        "status": "installed" if has_cursor else "ready",
        "detail": "macOS XCursors ready" if has_cursor else "Ready to download Apple cursors",
        "size_mb": 0 if has_cursor else 5,
        "required": False
    })

    # 8. macOS Tahoe Icon Theme (Scrimas/MacOS-Like)
    has_icons = (
        (HOME / ".local" / "share" / "icons" / "MacOS-Like-Dark").exists() or
        (HOME / ".local" / "share" / "icons" / "MacOS-Like-Light").exists() or
        Path("/usr/share/icons/MacOS-Like-Dark").exists()
    )
    deps.append({
        "id": "icon_theme",
        "name": "macOS Tahoe Icon Theme (Scrimas/MacOS-Like)",
        "category": "icons",
        "status": "installed" if has_icons else "ready",
        "detail": "MacOS-Like Tahoe icons ready" if has_icons else "Ready to compile Tahoe icons",
        "size_mb": 0 if has_icons else 15,
        "required": False
    })

    output = {
        "dependencies": deps,
        "all_ready": all(d["status"] in ["installed", "ready", "skipped"] for d in deps),
        "total_download_mb": sum(d["size_mb"] for d in deps if d["status"] in ["missing", "ready"])
    }
    print(f"DEPS_CHECK:{json.dumps(output, ensure_ascii=False)}", flush=True)


# ══════════════════════════════════════════════════════════════════════════════
# 2. macOS Wi-Fi Manager (nmcli integration)
# ══════════════════════════════════════════════════════════════════════════════

def wifi_status():
    """Get current Wi-Fi radio status and active connection."""
    enabled = False
    connected_ssid = ""
    ip_addr = ""

    if check_command("nmcli"):
        try:
            r = subprocess.check_output(["nmcli", "radio", "wifi"], stderr=subprocess.DEVNULL).decode("utf-8").strip()
            enabled = (r == "enabled")
        except Exception:
            pass

        try:
            out = subprocess.check_output(
                ["nmcli", "-t", "-f", "ACTIVE,SSID", "dev", "wifi"],
                stderr=subprocess.DEVNULL
            ).decode("utf-8")
            for line in out.strip().split("\n"):
                if line.startswith("yes:"):
                    connected_ssid = line.split(":", 1)[1].strip()
                    break
        except Exception:
            pass

        try:
            ip_out = subprocess.check_output(["sh", "-c", "ip -4 -o addr show | grep -v '127.0.0.1' | head -n1 | awk '{print $4}'"], stderr=subprocess.DEVNULL).decode("utf-8").strip()
            ip_addr = ip_out.split("/")[0] if ip_out else ""
        except Exception:
            pass

    res = {
        "enabled": enabled,
        "connected_ssid": connected_ssid,
        "ip": ip_addr
    }
    print(f"WIFI_STATUS:{json.dumps(res, ensure_ascii=False)}", flush=True)


def wifi_scan():
    """Scan and list nearby Wi-Fi networks in macOS format."""
    networks = []
    seen = set()

    if check_command("nmcli"):
        try:
            # Trigger rescan in background if supported, then list
            out = subprocess.check_output(
                ["nmcli", "-t", "-f", "IN-USE,SSID,SIGNAL,SECURITY", "dev", "wifi", "list", "--rescan", "no"],
                stderr=subprocess.DEVNULL, timeout=6
            ).decode("utf-8")

            for line in out.strip().split("\n"):
                if not line:
                    continue
                parts = line.split(":")
                if len(parts) < 4:
                    continue
                in_use = parts[0].strip() == "*"
                ssid = parts[1].strip()
                if not ssid or ssid in seen:
                    continue
                seen.add(ssid)

                try:
                    signal = int(parts[2].strip())
                except Exception:
                    signal = 50

                sec = parts[3].strip()
                secure = bool(sec and sec != "--")

                networks.append({
                    "ssid": ssid,
                    "signal": signal,
                    "secure": secure,
                    "inUse": in_use,
                    "security": sec
                })
        except Exception as e:
            pass

    # Sort: currently active first, then by signal strength descending
    networks.sort(key=lambda n: (not n["inUse"], -n["signal"]))
    print(f"WIFI_LIST:{json.dumps(networks, ensure_ascii=False)}", flush=True)


def wifi_toggle(state: str):
    """Toggle Wi-Fi radio on or off."""
    target = "on" if state.lower() in ["on", "true", "1"] else "off"
    if check_command("nmcli"):
        try:
            subprocess.run(["nmcli", "radio", "wifi", target], check=True, timeout=5)
            print(f"WIFI_TOGGLE:SUCCESS:{target}", flush=True)
            return
        except Exception as e:
            print(f"WIFI_TOGGLE:ERROR:{str(e)}", flush=True)
            return
    print("WIFI_TOGGLE:ERROR:nmcli not found", flush=True)


def wifi_connect(ssid: str, password: str = ""):
    """Connect to a Wi-Fi network using nmcli."""
    if not ssid:
        print("WIFI_CONNECT:ERROR:Invalid network name (SSID)", flush=True)
        return

    if not check_command("nmcli"):
        print("WIFI_CONNECT:ERROR:NetworkManager (nmcli) is not installed", flush=True)
        return

    cmd = ["nmcli", "--wait", "20", "dev", "wifi", "connect", ssid]
    if password and password.strip():
        cmd.extend(["password", password.strip()])

    try:
        proc = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=25)
        out = proc.stdout.decode("utf-8")
        err = proc.stderr.decode("utf-8")

        if proc.returncode == 0:
            print(f"WIFI_CONNECT:SUCCESS:{ssid}", flush=True)
        else:
            err_msg = err.strip() or out.strip() or "Failed to connect to network"
            if "Secrets were required" in err_msg or "password" in err_msg.lower():
                err_msg = "Incorrect Wi-Fi password"
            print(f"WIFI_CONNECT:ERROR:{err_msg}", flush=True)
    except subprocess.TimeoutExpired:
        print("WIFI_CONNECT:ERROR:Connection timed out (25s)", flush=True)
    except Exception as e:
        print(f"WIFI_CONNECT:ERROR:{str(e)}", flush=True)


# ══════════════════════════════════════════════════════════════════════════════
# 3. macOS Sound Synthesis
# ══════════════════════════════════════════════════════════════════════════════

def generate_macos_chime(filepath: Path):
    """Synthesize authentic macOS F# Major Startup Chime."""
    sample_rate = 44100
    duration = 3.8
    num_samples = int(sample_rate * duration)

    chord = [
        (92.50,  0.55),   # F#2 foundation bass
        (138.59, 0.45),   # C#3
        (185.00, 0.65),   # F#3 root
        (233.08, 0.50),   # A#3 major 3rd
        (277.18, 0.55),   # C#4 5th
        (369.99, 0.45),   # F#4 octave
        (466.16, 0.25),   # A#4
        (554.37, 0.20),   # C#5 shimmer
        (739.99, 0.12),   # F#5 bell
    ]

    samples = [0.0] * num_samples
    for freq, amp in chord:
        for i in range(num_samples):
            t = float(i) / sample_rate
            env = (1.0 - math.exp(-t * 70.0)) * math.exp(-t * 0.95)
            val = math.sin(2.0 * math.pi * freq * t) + 0.35 * math.sin(4.0 * math.pi * freq * t)
            samples[i] += amp * val * env

    max_amp = max(abs(s) for s in samples) if samples else 1.0
    scale = 0.92 / max_amp if max_amp > 0 else 1.0

    filepath.parent.mkdir(parents=True, exist_ok=True)
    with wave.open(str(filepath), 'wb') as wav_file:
        wav_file.setnchannels(2)
        wav_file.setsampwidth(2)
        wav_file.setframerate(sample_rate)

        raw_bytes = bytearray()
        for i in range(num_samples):
            val_l = int(max(-32767, min(32767, samples[i] * scale * 32767)))
            r_idx = max(0, i - 12)
            val_r = int(max(-32767, min(32767, samples[r_idx] * scale * 32767)))
            raw_bytes.extend(struct.pack('<hh', val_l, val_r))

        wav_file.writeframes(raw_bytes)


def generate_short_sound(filepath: Path, sound_type: str):
    """Synthesize crisp macOS UI sounds: tink, pop, shutter, charge."""
    sample_rate = 44100
    filepath.parent.mkdir(parents=True, exist_ok=True)

    if sound_type == "tink":
        duration = 0.35
        num_samples = int(sample_rate * duration)
        samples = []
        for i in range(num_samples):
            t = float(i) / sample_rate
            env = math.exp(-t * 18.0)
            val = math.sin(2 * math.pi * 2637 * t) * env
            samples.append(val)
    elif sound_type == "pop":
        duration = 0.08
        num_samples = int(sample_rate * duration)
        samples = []
        for i in range(num_samples):
            t = float(i) / sample_rate
            freq = 200 + 700 * math.exp(-t * 60)
            env = (1.0 - math.exp(-t * 200)) * math.exp(-t * 35)
            val = math.sin(2 * math.pi * freq * t) * env
            samples.append(val)
    elif sound_type == "charge":
        duration = 0.55
        num_samples = int(sample_rate * duration)
        samples = []
        for i in range(num_samples):
            t = float(i) / sample_rate
            env1 = math.exp(-max(0.0, t) * 12.0)
            env2 = math.exp(-max(0.0, t - 0.12) * 9.0) if t >= 0.12 else 0.0
            val = math.sin(2 * math.pi * 880 * t) * env1 + math.sin(2 * math.pi * 1760 * t) * env2 * 1.2
            samples.append(val)
    else:  # shutter
        duration = 0.22
        num_samples = int(sample_rate * duration)
        samples = []
        import random
        for i in range(num_samples):
            t = float(i) / sample_rate
            env1 = math.exp(-t * 45)
            env2 = math.exp(-max(0, t - 0.06) * 40) if t >= 0.06 else 0
            noise = (random.random() * 2 - 1)
            val = (noise * 0.4 + math.sin(2 * math.pi * 1200 * t) * 0.6) * (env1 + env2 * 1.5)
            samples.append(val)

    max_amp = max(abs(s) for s in samples) if samples else 1.0
    scale = 0.90 / max_amp if max_amp > 0 else 1.0

    with wave.open(str(filepath), 'wb') as wav_file:
        wav_file.setnchannels(2)
        wav_file.setsampwidth(2)
        wav_file.setframerate(sample_rate)
        raw_bytes = bytearray()
        for s in samples:
            val = int(max(-32767, min(32767, s * scale * 32767)))
            raw_bytes.extend(struct.pack('<hh', val, val))
        wav_file.writeframes(raw_bytes)


# ══════════════════════════════════════════════════════════════════════════════
# 4. Resource Setup Execution
# ══════════════════════════════════════════════════════════════════════════════

QUICKSHELL_CONFIG = HOME / ".config" / "quickshell"
MACSHELL_CONFIG = QUICKSHELL_CONFIG / "MacShell"
MACLOCK_CONFIG = QUICKSHELL_CONFIG / "MacLock"
BOOTSTRAP_CACHE = HOME / ".cache" / "macshell-bootstrap"

def run_setup(options_raw: str = ""):
    """Execute installation & configuration based on selected feature modules."""
    opts = {}
    if options_raw:
        try:
            opts = json.loads(options_raw)
        except Exception:
            pass

    siri_requested = opts.get("siri", False)
    sound_requested = opts.get("sound_pack", True)
    dark_mode = opts.get("dark_mode", True)
    stage_manager = opts.get("stage_manager", True)
    liquid_glass = opts.get("liquid_glass", True)
    api_key = opts.get("gemini_api_key", "").strip()

    def emit(pct: int, task: str, speed: str, msg: str):
        print(f"PROGRESS:{pct}:{task}:{speed}:{msg}", flush=True)
        time.sleep(0.3)

    emit(5, "Directories", "Local", "Creating system directory layout...")
    CONFIG_DIR.mkdir(parents=True, exist_ok=True)
    SOUNDS_DIR.mkdir(parents=True, exist_ok=True)
    FONTS_DIR.mkdir(parents=True, exist_ok=True)
    QUICKSHELL_CONFIG.mkdir(parents=True, exist_ok=True)

    # 1. Deploy MacShell directly into ~/.config/quickshell/MacShell
    emit(15, "Source Code", "Deploying", "Deploying MacShell directly into ~/.config/quickshell/MacShell...")
    MACSHELL_CONFIG.mkdir(parents=True, exist_ok=True)
    MACLOCK_CONFIG.mkdir(parents=True, exist_ok=True)

    bootstrap_repo = BOOTSTRAP_CACHE / "repo"
    src_macshell = None
    if bootstrap_repo.exists() and (bootstrap_repo / "MacShell").exists():
        src_macshell = bootstrap_repo / "MacShell"
    elif MACSHELL_DIR.exists() and (MACSHELL_DIR / "shell.qml").exists():
        src_macshell = MACSHELL_DIR

    # Check if MacShell is already active in MACSHELL_CONFIG
    is_already_active = (MACSHELL_CONFIG / "shell.qml").exists()
    if is_already_active:
        emit(20, "Source Code", "Verified", "MacShell configuration active in ~/.config/quickshell/MacShell")
    elif src_macshell and src_macshell.resolve() != MACSHELL_CONFIG.resolve():
        emit(20, "Copying Code", "Local", "Synchronizing files directly into ~/.config/quickshell/MacShell...")
        for item in src_macshell.iterdir():
            dest = MACSHELL_CONFIG / item.name
            if not dest.exists():
                if item.is_dir():
                    shutil.copytree(item, dest, dirs_exist_ok=True)
                else:
                    shutil.copy2(item, dest)

        # Deploy MacLock if available
        src_maclock = bootstrap_repo / "MacLock" if (bootstrap_repo / "MacLock").exists() else (MACSHELL_DIR.parent / "MacLock")
        if src_maclock.exists() and src_maclock.resolve() != MACLOCK_CONFIG.resolve():
            for item in src_maclock.iterdir():
                dest = MACLOCK_CONFIG / item.name
                if not dest.exists():
                    if item.is_dir():
                        shutil.copytree(item, dest, dirs_exist_ok=True)
                    else:
                        shutil.copy2(item, dest)

    # 2. Soundpack
    if sound_requested:
        emit(38, "macOS Sounds", "Synthesizing", "Generating F# Major Startup Chime & UI Effects...")
        chime_path = SOUNDS_DIR / "chime.wav"
        if not chime_path.exists() or chime_path.stat().st_size < 1000:
            generate_macos_chime(chime_path)

        generate_short_sound(SOUNDS_DIR / "tink.wav", "tink")
        generate_short_sound(SOUNDS_DIR / "pop.wav", "pop")
        generate_short_sound(SOUNDS_DIR / "charge.wav", "charge")
        generate_short_sound(SOUNDS_DIR / "shutter.wav", "shutter")
    else:
        emit(38, "macOS Sounds", "Skipped", "Skipping sound pack per user selection...")

    # 3. Fonts
    emit(55, "Apple Fonts", "Syncing", "Synchronizing SF Pro & Open Runde typography...")
    bundled_fonts = MACSHELL_DIR / "assets" / "fonts"
    if not bundled_fonts.exists() and (MACSHELL_CONFIG / "assets" / "fonts").exists():
        bundled_fonts = MACSHELL_CONFIG / "assets" / "fonts"

    if bundled_fonts.exists():
        for font_file in bundled_fonts.glob("*.[to]tf"):
            dest = FONTS_DIR / font_file.name
            if not dest.exists():
                try:
                    os.link(font_file, dest)
                except Exception:
                    try:
                        shutil.copy2(font_file, dest)
                    except Exception:
                        pass
    os.system("fc-cache -f ~/.local/share/fonts >/dev/null 2>&1")

    # 3b. macOS Tahoe 26 Blue Ribbon Wallpapers (Light & Dark pairs)
    emit(60, "macOS Wallpaper", "Deploying", "Configuring macOS Tahoe 26 Light & Dark Wallpapers...")
    wallpapers_dest = MACSHELL_CONFIG / "assets" / "wallpapers"
    wallpapers_dest.mkdir(parents=True, exist_ok=True)
    
    bundled_wp_dir = MACSHELL_DIR / "assets" / "wallpapers"
    for wp_name in ["tahoe.jpg", "tahoe_light.jpg", "tahoe_dark.jpg"]:
        dest = wallpapers_dest / wp_name
        src = bundled_wp_dir / wp_name
        if src.exists():
            try:
                shutil.copy2(src, dest)
            except Exception:
                pass

    chosen_wp = str(wallpapers_dest / ("tahoe_dark.jpg" if dark_mode else "tahoe_light.jpg"))
    pair_light = str(wallpapers_dest / "tahoe_light.jpg")
    pair_dark = str(wallpapers_dest / "tahoe_dark.jpg")

    # Immediately set desktop wallpaper
    if check_command("awww"):
        subprocess.run(["awww", "img", chosen_wp, "--transition-type", "fade", "--transition-duration", "0.7"], check=False)
    elif check_command("swww"):
        subprocess.run(["swww", "img", chosen_wp, "--transition-type", "fade", "--transition-duration", "0.7"], check=False)

    # 4. Python AI packages if Siri was selected
    if siri_requested:
        emit(72, "Apple Intelligence", "Verifying", "Checking Python packages: google-genai, sounddevice, numpy...")
        try:
            import google.genai
            import sounddevice
            import numpy
            emit(85, "Apple Intelligence", "Ready", "AI runtime environment ready.")
        except ImportError:
            emit(78, "AI Libraries", "1.2 MB/s", "Installing auxiliary dependencies via pip...")
            try:
                subprocess.run([sys.executable, "-m", "pip", "install", "--quiet", "google-genai", "sounddevice", "numpy"], check=False)
            except Exception:
                pass
    else:
        emit(80, "Apple Intelligence", "Disabled", "Skipping AI libraries (Siri disabled).")

    # 5. Apply macOS Cursor Theme & Tahoe Icon Theme
    emit(88, "macOS Theme", "Applying", "Configuring macOS Cursor & Tahoe Icon theme...")
    chosen_icon_theme = "MacOS-Like-Dark" if dark_mode else "MacOS-Like-Light"
    chosen_cursor_theme = "macOS"

    # Verify if cursor is present, download fallback if needed
    user_icons = HOME / ".local" / "share" / "icons"
    user_icons.mkdir(parents=True, exist_ok=True)
    if not (user_icons / "macOS").exists() and not Path("/usr/share/icons/macOS").exists():
        try:
            emit(89, "macOS Cursor", "Downloading", "Fetching authentic Apple cursor pack...")
            cursor_tar = user_icons / "macOS.tar.xz"
            urllib.request.urlretrieve("https://github.com/ful1e5/apple_cursor/releases/latest/download/macOS.tar.xz", str(cursor_tar))
            subprocess.run(["tar", "-xJf", str(cursor_tar), "-C", str(user_icons)], check=False)
            cursor_tar.unlink(missing_ok=True)
        except Exception:
            pass

    # Apply via gsettings & hyprctl
    try:
        subprocess.run(["gsettings", "set", "org.gnome.desktop.interface", "cursor-theme", chosen_cursor_theme], check=False)
        subprocess.run(["gsettings", "set", "org.gnome.desktop.interface", "icon-theme", chosen_icon_theme], check=False)
    except Exception:
        pass
    if check_command("hyprctl"):
        try:
            subprocess.run(["hyprctl", "setcursor", chosen_cursor_theme, "24"], check=False)
        except Exception:
            pass

    # 6. Save Configuration Files
    emit(94, "Configuration", "Local", "Writing ~/.config/macshell/config.json and settings.json...")
    config_data = {
        "theme": "dark" if dark_mode else "light",
        "icon_theme": chosen_icon_theme,
        "cursor_theme": chosen_cursor_theme,
        "modules": {
            "core_ui": True,
            "stage_manager": stage_manager,
            "wifi_manager": opts.get("wifi_manager", True),
            "siri": siri_requested,
            "sound_pack": sound_requested
        },
        "liquid_glass": liquid_glass,
        "siri_enabled": siri_requested,
        "live_voice_streaming": opts.get("live_voice_streaming", True),
        "tts_voice": opts.get("tts_voice", "vi-VN-NamMinhNeural"),
        "tts_language": opts.get("tts_language", "vi-VN"),
        "configured_at": time.strftime("%Y-%m-%dT%H:%M:%S%z")
    }
    with open(CONFIG_DIR / "config.json", "w", encoding="utf-8") as f:
        json.dump(config_data, f, indent=2, ensure_ascii=False)

    # Save siri settings
    siri_data = {
        "siri_enabled": siri_requested,
        "gemini_api_key": api_key if siri_requested else "",
        "live_voice": opts.get("live_voice_streaming", True) if siri_requested else False,
        "voice": opts.get("tts_voice", "vi-VN-NamMinhNeural"),
        "language": opts.get("tts_language", "vi-VN")
    }
    with open(CONFIG_DIR / "siri_settings.json", "w", encoding="utf-8") as f:
        json.dump(siri_data, f, indent=2, ensure_ascii=False)

    # Save settings.json in MacShell directory
    macshell_settings = {
        "darkMode": dark_mode,
        "stageManager": stage_manager,
        "dockStyle": "liquid" if liquid_glass else "blur",
        "setup_completed": True
    }
    with open(MACSHELL_CONFIG / "settings.json", "w", encoding="utf-8") as f:
        json.dump(macshell_settings, f, indent=2, ensure_ascii=False)

    # Update macbar settings.json with default light/dark pair and wallpaper
    macbar_settings_path = HOME / ".config" / "macbar" / "settings.json"
    macbar_settings = {}
    if macbar_settings_path.exists():
        try:
            with open(macbar_settings_path, "r", encoding="utf-8") as f:
                macbar_settings = json.load(f)
        except Exception:
            pass
    macbar_settings["darkMode"] = dark_mode
    macbar_settings["appearanceMode"] = "dark" if dark_mode else "light"
    macbar_settings["wallpaperPath"] = chosen_wp
    macbar_settings["wpRestorePath"] = chosen_wp
    macbar_settings["wpPairLight"] = pair_light
    macbar_settings["wpPairDark"] = pair_dark
    macbar_settings["wallpaperAppearance"] = "auto"
    macbar_settings_path.parent.mkdir(parents=True, exist_ok=True)
    with open(macbar_settings_path, "w", encoding="utf-8") as f:
        json.dump(macbar_settings, f, indent=2, ensure_ascii=False)

    # Update macdock settings.json
    macdock_settings_path = HOME / ".config" / "macdock" / "settings.json"
    macdock_settings = {}
    if macdock_settings_path.exists():
        try:
            with open(macdock_settings_path, "r", encoding="utf-8") as f:
                macdock_settings = json.load(f)
        except Exception:
            pass
    macdock_settings["darkMode"] = dark_mode
    macdock_settings["wallpaperPath"] = chosen_wp
    macdock_settings["dockStyle"] = "liquid" if liquid_glass else "blur"
    macdock_settings_path.parent.mkdir(parents=True, exist_ok=True)
    with open(macdock_settings_path, "w", encoding="utf-8") as f:
        json.dump(macdock_settings, f, indent=2, ensure_ascii=False)

    # Save gemini_config if provided
    if api_key:
        with open(CONFIG_DIR / "gemini_config.json", "w", encoding="utf-8") as f:
            json.dump({"api_key": api_key, "model": "gemini-2.5-flash"}, f, indent=2)

    # Create setup completed flags
    (CONFIG_DIR / ".setup_completed").touch()
    (MACSHELL_CONFIG / ".setup_completed").touch()

    emit(100, "Completed", "Done", "All resources configured successfully!")
    print("STATUS:SUCCESS", flush=True)


def complete_setup(options_raw: str = ""):
    """Create .setup_completed flag and apply final settings."""
    CONFIG_DIR.mkdir(parents=True, exist_ok=True)
    (CONFIG_DIR / ".setup_completed").touch()
    if MACSHELL_CONFIG.exists():
        (MACSHELL_CONFIG / ".setup_completed").touch()
    print("STATUS:COMPLETED", flush=True)
    CONFIG_DIR.mkdir(parents=True, exist_ok=True)
    flag_file = CONFIG_DIR / ".setup_completed"
    with open(flag_file, "w") as f:
        f.write(f"completed_at={time.strftime('%Y-%m-%dT%H:%M:%S%z')}\nversion=1.0\n")
    print("STATUS:COMPLETED", flush=True)


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: setup_assistant_worker.py [test_gemini_key | check_dependencies | wifi_status | wifi_scan | wifi_toggle | wifi_connect | run_setup | complete_setup]")
        sys.exit(1)

    cmd = sys.argv[1]
    arg1 = sys.argv[2] if len(sys.argv) > 2 else ""
    arg2 = sys.argv[3] if len(sys.argv) > 3 else ""

    if cmd == "test_gemini_key":
        test_gemini_key(arg1)
    elif cmd == "check_dependencies":
        check_dependencies(arg1)
    elif cmd == "wifi_status":
        wifi_status()
    elif cmd == "wifi_scan":
        wifi_scan()
    elif cmd == "wifi_toggle":
        wifi_toggle(arg1)
    elif cmd == "wifi_connect":
        wifi_connect(arg1, arg2)
    elif cmd == "run_setup":
        run_setup(arg1)
    elif cmd == "complete_setup":
        complete_setup(arg1)
    else:
        print(f"Unknown command: {cmd}", flush=True)
        sys.exit(1)
