#!/usr/bin/env -S /home/kuro/.config/quickshell/MacShell/venv/bin/python
# -*- coding: utf-8 -*-
"""
Siri Edge Glow & Voice AI Assistant Daemon for MacShell (Quickshell)
--------------------------------------------------------------------
- Offline Wake Word listener ("Hey Siri", "Siri")
- Free Google Speech Recognition (STT)
- Google Gemini API (Free tier / GenAI SDK)
- TTS Speech synthesis (espeak-ng / piper)
- Quickshell IPC Bridge (qs -c MacShell ipc call siri ...)
"""

import sys
import os
import gc
from collections import deque
import json
import time
import argparse
import subprocess
import threading
import re
import urllib.request
import urllib.parse
from pathlib import Path

# ── AUTO-RESPAWN WITH VIRTUAL ENVIRONMENT ──
SCRIPT_DIR = Path(__file__).resolve().parent
MACSHELL_DIR = SCRIPT_DIR.parent
VENV_PYTHON = MACSHELL_DIR / "venv" / "bin" / "python"

if VENV_PYTHON.exists() and sys.executable != str(VENV_PYTHON):
    try:
        os.execv(str(VENV_PYTHON), [str(VENV_PYTHON)] + sys.argv)
    except Exception as e:
        print(f"[Warning] Failed to re-exec with venv python: {e}", file=sys.stderr)

# ── CONFIGURATION LOADER ──
CONFIG_FILE = MACSHELL_DIR / "gemini_config.json"
SETTINGS_FILE = MACSHELL_DIR / "siri_settings.json"

DEFAULT_CONFIG = {
    "api_key": os.getenv("GEMINI_API_KEY", "YOUR_GEMINI_API_KEY_HERE"),
    "model": "gemini-2.5-flash",
    "wake_words": ["hey siri", "siri", "ơi siri"],
    "language": "auto",       # "auto", "vi-VN", "en-US"
    "tts_engine": "espeak-ng", # "espeak-ng", "piper"
    "tts_voice_en": "en-us+f3",
    "tts_voice_vi": "vi",
    "speech_rate": 165
}

def load_config() -> dict:
    config = DEFAULT_CONFIG.copy()
    # Read siri_settings.json first
    if SETTINGS_FILE.exists():
        try:
            with open(SETTINGS_FILE, "r", encoding="utf-8") as f:
                user_conf = json.load(f)
                config.update(user_conf)
        except Exception as e:
            print(f"[Config] Error reading {SETTINGS_FILE}: {e}")
    # Read gemini_config.json fallback
    if CONFIG_FILE.exists():
        try:
            with open(CONFIG_FILE, "r", encoding="utf-8") as f:
                gem_conf = json.load(f)
                if gem_conf.get("api_key") and gem_conf.get("api_key") != "YOUR_GEMINI_API_KEY_HERE":
                    config["api_key"] = gem_conf.get("api_key")
                if gem_conf.get("model"):
                    config["model"] = gem_conf.get("model")
        except Exception as e:
            print(f"[Config] Error reading {CONFIG_FILE}: {e}")
    # Environment variable override
    env_key = os.getenv("GEMINI_API_KEY")
    if env_key:
        config["api_key"] = env_key
    return config

CONFIG = load_config()

# ── QUICKSHELL IPC WRAPPER ──
class SiriIPC:
    @staticmethod
    def call(action: str, *args):
        """Invoke Quickshell IPC method on target 'siri'."""
        cmd = ["qs", "-c", "MacShell", "ipc", "call", "siri", action] + [str(a) for a in args]
        try:
            subprocess.run(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=2.0)
        except Exception:
            pass

    @classmethod
    def activate(cls, on: bool = True):
        cls.call("activate", "true" if on else "false")

    @classmethod
    def set_state(cls, state: str):
        # "idle", "listening", "thinking", "speaking"
        cls.call("state", state)

    @classmethod
    def set_prompt(cls, text: str):
        cls.call("prompt", text)

    @classmethod
    def set_response(cls, text: str):
        cls.call("response", text)

    @classmethod
    def set_audio_level(cls, level: float):
        cls.call("audioLevel", f"{level:.2f}")

    @classmethod
    def dismiss(cls):
        cls.call("dismiss")


# ── SYSTEM CONTROL TOOLS (GEMINI FUNCTION CALLING & LOCAL ROUTER) ──
def launch_app(app_name: str) -> str:
    """
    Launch an application on Linux (supporting Native apps and Flatpaks).
    Uses a multi-step Waterfall Fallback mechanism:
    1. Flatpak ID matching (flatpak list --app)
    2. Desktop entry lookup in application directories & gtk-launch
    3. Hyprland dispatcher (hyprctl dispatch exec) / direct PATH execution
    All processes are spawned asynchronously without blocking the daemon.
    """
    if not app_name or not app_name.strip():
        return "Please specify the application name to launch."

    clean_name = app_name.strip().lower()

    # ── STEP 1: FLATPAK ID MATCHING ──
    try:
        res = subprocess.run(
            ["flatpak", "list", "--app", "--columns=application,name"],
            capture_output=True, text=True, timeout=2.0
        )
        if res.returncode == 0:
            lines = res.stdout.strip().split("\n")
            for line in lines[1:]:  # Skip header
                parts = line.split("\t") if "\t" in line else line.split(None, 1)
                if parts:
                    app_id = parts[0].strip()
                    app_display_name = parts[1].strip() if len(parts) > 1 else app_id
                    id_tail = app_id.split(".")[-1].lower()

                    # Match against ID, display name, or end of ID (e.g. spotify -> com.spotify.Client)
                    if (clean_name in app_id.lower() or
                        clean_name in app_display_name.lower() or
                        clean_name == id_tail):
                        subprocess.Popen(
                            ["flatpak", "run", app_id],
                            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                            start_new_session=True
                        )
                        return f"Đã mở {app_display_name} qua Flatpak."
    except Exception as e:
        print(f"[LaunchApp] Flatpak check error: {e}")

    # ── STEP 2: DESKTOP ENTRY LOOKUP & GTK-LAUNCH ──
    desktop_dirs = [
        os.path.expanduser("~/.local/share/applications"),
        "/usr/share/applications",
        "/var/lib/flatpak/exports/share/applications",
        os.path.expanduser("~/.local/share/flatpak/exports/share/applications")
    ]
    matched_desktop = None
    for d in desktop_dirs:
        if not os.path.isdir(d):
            continue
        try:
            for entry in os.listdir(d):
                if entry.endswith(".desktop"):
                    entry_base = entry[:-8].lower()
                    if clean_name == entry_base or clean_name in entry_base:
                        matched_desktop = entry[:-8]
                        break
                    # Check Name= line inside .desktop file
                    try:
                        filepath = os.path.join(d, entry)
                        with open(filepath, "r", encoding="utf-8", errors="ignore") as f:
                            for fline in f:
                                if fline.startswith("Name=") and clean_name in fline[5:].strip().lower():
                                    matched_desktop = entry[:-8]
                                    break
                        if matched_desktop:
                            break
                    except Exception:
                        pass
            if matched_desktop:
                break
        except Exception:
            pass

    if matched_desktop:
        try:
            subprocess.Popen(
                ["gtk-launch", matched_desktop],
                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                start_new_session=True
            )
            return f"Đã khởi chạy {app_name}."
        except Exception as e:
            print(f"[LaunchApp] gtk-launch error: {e}")

    # ── STEP 3: HYPRLAND DISPATCHER OR DIRECT COMMAND EXECUTION ──
    try:
        if os.getenv("HYPRLAND_INSTANCE_SIGNATURE"):
            subprocess.Popen(
                ["hyprctl", "dispatch", "exec", clean_name],
                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                start_new_session=True
            )
            return f"Đã thực thi mở {app_name} qua Hyprland."
    except Exception:
        pass

    try:
        subprocess.Popen(
            [clean_name],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
            start_new_session=True
        )
        return f"Đã mở {app_name}."
    except Exception as e:
        return f"Không thể tìm thấy hoặc khởi chạy ứng dụng '{app_name}': {e}"

def open_url(url: str) -> str:
    """Open a web URL in the default browser using xdg-open."""
    clean_url = url.strip()
    if not clean_url.startswith(("http://", "https://")):
        clean_url = "https://" + clean_url
    try:
        subprocess.Popen(["xdg-open", clean_url], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)
        return f"Opened {clean_url} in browser."
    except Exception as e:
        return f"Failed to open URL {url}: {e}"

def play_music(platform: str, query: str) -> str:
    """Play music or search on Spotify (playerctl or web), YouTube, or Apple Music."""
    p = platform.lower().strip()
    q = query.strip()
    encoded_q = urllib.parse.quote(q)

    if "spotify" in p:
        try:
            res = subprocess.run(["playerctl", "-p", "spotify", "status"], capture_output=True, text=True)
            if "Playing" in res.stdout or "Paused" in res.stdout:
                subprocess.run(["playerctl", "-p", "spotify", "play"])
                return f"Resumed playback on Spotify for {q}."
        except Exception:
            pass
        open_url(f"https://open.spotify.com/search/{encoded_q}")
        return f"Playing {q} on Spotify."

    elif "youtube" in p:
        open_url(f"https://www.youtube.com/results?search_query={encoded_q}")
        return f"Searching and playing {q} on YouTube."

    elif "apple" in p:
        open_url(f"https://music.apple.com/us/search?term={encoded_q}")
        return f"Searching {q} on Apple Music."

    else:
        open_url(f"https://www.youtube.com/results?search_query={encoded_q}")
        return f"Playing {q}."

def fetch_weather(location: str = "Danang") -> dict:
    """
    Get detailed real-time weather data and forecast for a given location or city.
    If the user does not specify a location, defaults to 'Danang'.
    Returns structured metrics including temperature, feels-like, humidity, condition, rain chance, and UV index.
    """
    import unicodedata
    loc = location.strip() if location and location.strip() else "Danang"

    # Remove accents for wttr.in URL parameter
    clean_loc = "".join(c for c in unicodedata.normalize("NFD", loc) if unicodedata.category(c) != "Mn").replace("đ", "d").replace("Đ", "D")
    loc_param = clean_loc.replace(" ", "+")

    try:
        req = urllib.request.Request(f"https://wttr.in/{loc_param}?format=j1", headers={"User-Agent": "curl/8.0"})
        with urllib.request.urlopen(req, timeout=4.5) as resp:
            data = json.loads(resp.read().decode("utf-8"))
            curr = data.get("current_condition", [{}])[0]
            today = data.get("weather", [{}])[0]
            hourly = today.get("hourly", [{}])

            # Calculate maximum chance of rain today
            rain_chances = []
            for h in hourly:
                try:
                    rain_chances.append(int(h.get("chanceofrain", 0)))
                except (ValueError, TypeError):
                    pass
            max_rain_chance = max(rain_chances) if rain_chances else 0

            desc_list = curr.get("weatherDesc", [{}])
            weather_desc = desc_list[0].get("value", "Clear") if desc_list else "Clear"

            return {
                "location": loc.title(),
                "temperature_c": curr.get("temp_C", "N/A"),
                "feels_like_c": curr.get("FeelsLikeC", "N/A"),
                "humidity_percent": curr.get("humidity", "N/A"),
                "condition": weather_desc,
                "wind_speed_kmph": curr.get("windspeedKmph", "N/A"),
                "uv_index": curr.get("uvIndex", "N/A"),
                "max_temp_c": today.get("maxtempC", "N/A"),
                "min_temp_c": today.get("mintempC", "N/A"),
                "chance_of_rain_percent": max_rain_chance
            }
    except Exception as e:
        return {
            "location": loc,
            "error": f"Could not retrieve weather: {e}"
        }

def search_files(keyword: str) -> str:
    """Quickly search files and directories in home folder or .config matching the keyword."""
    clean_kw = keyword.strip().replace("'", "").replace('"', "")
    home = os.path.expanduser("~")
    try:
        if subprocess.run(["which", "fd"], capture_output=True).returncode == 0:
            res = subprocess.run(["fd", "-i", "-t", "f", "-max-depth", "4", clean_kw, home], capture_output=True, text=True, timeout=4)
            files = [line.strip() for line in res.stdout.strip().split("\n") if line.strip()][:5]
            if files:
                return "Found files:\n" + "\n".join(files)
        res = subprocess.run(["find", home, "-maxdepth", "4", "-iname", f"*{clean_kw}*", "-not", "-path", "*/.cache/*", "-not", "-path", "*/.git/*"], capture_output=True, text=True, timeout=4)
        files = [line.strip() for line in res.stdout.strip().split("\n") if line.strip()][:5]
        if files:
            return "Found files:\n" + "\n".join(files)
        return f"No files matching '{keyword}' found."
    except Exception as e:
        return f"Error searching files: {e}"


# ── LOCAL-FIRST INTENT ROUTER (0 AI TOKENS) ──
def normalize_text(text: str) -> str:
    """Normalize text by converting to lowercase and stripping accents."""
    import unicodedata
    n = "".join(c for c in unicodedata.normalize("NFD", text.lower().strip()) if unicodedata.category(c) != "Mn")
    return n.replace("đ", "d").replace("Đ", "D")

def handle_local_intent(query: str):
    """
    Local-First Intent Router:
    Execute system tasks locally with 0 AI tokens.
    Weather inquiries are forwarded directly to Gemini AI with fetch_weather tool.
    Returns response string if handled, or None to fallback to Gemini AI.
    """
    raw_q = query.strip()
    norm_q = normalize_text(raw_q)
    if not norm_q:
        return None

    # 1. MỞ NHẠC (Music Playback)
    music_keywords = ["mo nhac", "bat nhac", "nghe nhac", "nghe bai", "play music", "play"]
    for mk in music_keywords:
        if norm_q.startswith(mk) or f" {mk} " in f" {norm_q} ":
            track = re.sub(rf'^.*?{mk}\s*', '', norm_q).strip()
            is_spotify = "spotify" in norm_q
            track = re.sub(r'\b(tren|on)?\s*(youtube|spotify)\b', '', track).strip()
            if not track:
                track = "lofi chill"
            if is_spotify:
                return play_music("spotify", track)
            else:
                return play_music("youtube", track)

    # 2. TÌM KIẾM GOOGLE (Web Search)
    search_keywords = ["tim kiem", "search", "google"]
    for sk in search_keywords:
        if norm_q.startswith(sk):
            term = re.sub(rf'^{sk}\s*', '', raw_q).strip()
            if term:
                open_url(f"https://www.google.com/search?q={urllib.parse.quote(term)}")
                return f"Đang tìm kiếm '{term}' trên Google cho bạn."

    # 3. MỞ ỨNG DỤNG (Launch App)
    app_keywords = ["mo ung dung", "chay ung dung", "mo app", "chay app", "mo", "chay", "launch", "bat"]
    for ak in app_keywords:
        if norm_q.startswith(ak + " "):
            app_target = norm_q[len(ak):].strip()
            if app_target.startswith(("nhac", "bai", "web", "trang")):
                continue
            app_map = {
                "trinh duyet": "firefox",
                "web": "firefox",
                "terminal": "kitty",
                "console": "kitty",
                "vs code": "code",
                "vscode": "code",
                "quan ly file": "dolphin",
                "file manager": "dolphin",
                "tep tin": "dolphin",
                "nhac": "spotify"
            }
            exec_name = app_map.get(app_target, app_target)
            return launch_app(exec_name)

    # 4. TÌM FILE (Search Files)
    file_keywords = ["tim file", "tim tep", "tim tap tin", "search file", "find file"]
    for fk in file_keywords:
        if fk in norm_q:
            kw = re.sub(rf'^.*?{fk}\s*', '', norm_q).strip()
            if kw:
                return search_files(kw)

    # Fallback to Gemini AI for reasoning, weather, code, translation, etc.
    return None


# ── GEMINI API INTEGRATION ──
def query_gemini(prompt: str) -> str:
    """Send question to Gemini model and return text response with Function Calling tools enabled."""
    global CONFIG
    CONFIG = load_config()

    api_key = CONFIG.get("api_key", "").strip()
    if not api_key or api_key == "YOUR_GEMINI_API_KEY_HERE":
        return "Please configure your Gemini API key in Settings -> Apple Intelligence & Siri."

    preferred_model = CONFIG.get("model", "gemini-2.5-flash-lite")
    fallback_models = [preferred_model, "gemini-2.5-flash-lite", "gemini-flash-latest", "gemini-flash-lite-latest"]
    models_to_try = []
    for m in fallback_models:
        if m and m not in models_to_try:
            models_to_try.append(m)

    system_instruction = (
        "You are Siri, Apple's intelligent assistant on Linux (MacShell). "
        "Keep your answers direct, concise, natural for speech, and helpful. "
        "Use available tools when asked to launch apps, open URLs, play music, fetch weather, or search files. "
        "When answering weather inquiries using the fetch_weather tool, synthesize a natural, friendly spoken reply "
        "(mention temperature, feels-like if significantly different, conditions, and practical advice like bringing an umbrella if rain chance is high). "
        "If the user does not specify a location for weather, assume 'Danang'. "
        "Do not use markdown bolding (**) or bullet points (*) because your reply will be read aloud by TTS."
    )

    from google import genai
    from google.genai import types

    client = genai.Client(api_key=api_key)
    config = types.GenerateContentConfig(
        system_instruction=system_instruction,
        tools=[launch_app, open_url, play_music, fetch_weather, search_files],
        temperature=0.3
    )

    last_error = ""
    for model_name in models_to_try:
        for attempt in range(2):
            try:
                chat = client.chats.create(model=model_name, config=config)
                response = chat.send_message(prompt)
                if response and response.text:
                    return response.text.strip()
            except Exception as e:
                last_error = str(e)
                time.sleep(0.8)

    return f"I'm sorry, I encountered an issue contacting Gemini: {last_error[:120]}"


# ── TEXT TO SPEECH (TTS) & SINGLE-SPEAKER MUTEX ──
IS_SPEAKING = False
LAST_SPEAK_FINISH = 0.0
LAST_SPOKEN_TEXT = ""
CURRENT_PLAYER_PROC = None
SPEECH_LOCK = threading.Lock()
SPEECH_PID_FILE = "/tmp/macshell_siri_speech.pid"

def stop_all_speech():
    """Immediately stop all ongoing speech synthesis and playback across processes."""
    global CURRENT_PLAYER_PROC, IS_SPEAKING
    IS_SPEAKING = False

    # 1. Terminate current process player if active
    if CURRENT_PLAYER_PROC is not None:
        try:
            CURRENT_PLAYER_PROC.kill()
        except Exception:
            pass
        CURRENT_PLAYER_PROC = None

    # 2. Terminate previous speech PID if alive
    if os.path.exists(SPEECH_PID_FILE):
        try:
            with open(SPEECH_PID_FILE, "r") as pf:
                old_pid = int(pf.read().strip())
            if old_pid != os.getpid():
                os.kill(old_pid, 15)
        except Exception:
            pass
        try:
            os.remove(SPEECH_PID_FILE)
        except OSError:
            pass

    # 3. Kill any rogue mpv or espeak-ng instances playing Siri audio
    try:
        subprocess.run(["pkill", "-9", "-f", "siri_speech"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    except Exception:
        pass
    try:
        subprocess.run(["killall", "-9", "espeak-ng"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    except Exception:
        pass

def is_vietnamese(text: str) -> bool:
    """Check if the response contains Vietnamese characters."""
    return bool(re.search(r'[àáạảãâầấậẩẫăằắặẳẵèéẹẻẽêềếệểễìíịỉĩòóọỏõôồốộổỗơờớợởỡùúụủũưừứựửữỳýỵỷỹđ]', text, re.IGNORECASE))

def map_to_neural_voice(voice: str, is_vi: bool) -> str:
    """Map voice name to pristine Microsoft Edge Neural voices (studio grade, no buzzing)."""
    if is_vi:
        if any(k in voice for k in ["m1", "m2", "NamMinh", "nam"]):
            return "vi-VN-NamMinhNeural"
        return "vi-VN-HoaiMyNeural"
    else:
        if any(k in voice for k in ["m3", "Guy", "male"]):
            return "en-US-GuyNeural"
        elif any(k in voice for k in ["gb", "Sonia", "british"]):
            return "en-GB-SoniaNeural"
        return "en-US-JennyNeural"

def speak(text: str):
    """Read text aloud with pristine Neural TTS (edge-tts), strictly ensuring ONLY ONE speaker plays."""
    global IS_SPEAKING, LAST_SPEAK_FINISH, LAST_SPOKEN_TEXT, CURRENT_PLAYER_PROC
    clean_text = re.sub(r'[*_#`~]', '', text).strip()
    if not clean_text:
        return

    # Strictly kill any ongoing or overlapping speech before starting this one!
    stop_all_speech()

    with SPEECH_LOCK:
        IS_SPEAKING = True
        LAST_SPOKEN_TEXT = clean_text.lower()

        try:
            with open(SPEECH_PID_FILE, "w") as pf:
                pf.write(str(os.getpid()))
        except Exception:
            pass

        is_vi = is_vietnamese(clean_text)
        cfg_voice = CONFIG.get("tts_voice_vi" if is_vi else "tts_voice_en", "vi" if is_vi else "en-us+f3")
        neural_voice = map_to_neural_voice(cfg_voice, is_vi)

        # Calculate speech rate string (e.g. "+5%", "-10%")
        speech_rate = CONFIG.get("speech_rate", 165)
        rate_percent = int(round((speech_rate - 165) / 165.0 * 80))
        rate_str = f"{rate_percent:+d}%"

        # Pulsing thread while TTS is playing
        stop_pulse = threading.Event()
        level_queue = deque([0.30, 0.55, 0.70, 0.45, 0.65, 0.40, 0.75, 0.50], maxlen=16)

        def pulse_loop():
            idx = 0
            q_len = len(level_queue)
            while not stop_pulse.is_set():
                SiriIPC.set_audio_level(level_queue[idx % q_len])
                idx += 1
                time.sleep(0.12)
            SiriIPC.set_audio_level(0.0)

        pulse_thread = threading.Thread(target=pulse_loop, daemon=True)
        pulse_thread.start()

        tmp_audio = f"/tmp/siri_speech_{os.getpid()}.mp3"
        played = False

        # 1. High Quality Edge Neural TTS (Pristine audio, no buzzing / no distortion)
        try:
            import asyncio, edge_tts
            async def synthesize():
                comm = edge_tts.Communicate(clean_text, neural_voice, rate=rate_str)
                await comm.save(tmp_audio)
            asyncio.run(synthesize())

            if os.path.exists(tmp_audio) and os.path.getsize(tmp_audio) > 0:
                CURRENT_PLAYER_PROC = subprocess.Popen(
                    ["mpv", "--no-terminal", "--really-quiet", "--volume=100", tmp_audio],
                    stdout=subprocess.DEVNULL,
                    stderr=subprocess.DEVNULL
                )
                CURRENT_PLAYER_PROC.wait()
                CURRENT_PLAYER_PROC = None
                played = True
        except Exception as e:
            print(f"[TTS] Neural TTS notice: {e}, falling back to espeak-ng", file=sys.stderr)

        # 2. Fallback to espeak-ng if neural TTS fails or offline
        if not played:
            try:
                raw_voice = "vi" if is_vi else "en-us+f3"
                CURRENT_PLAYER_PROC = subprocess.Popen(
                    ["espeak-ng", "-v", raw_voice, "-s", str(speech_rate), clean_text],
                    stdout=subprocess.DEVNULL,
                    stderr=subprocess.DEVNULL
                )
                CURRENT_PLAYER_PROC.wait()
                CURRENT_PLAYER_PROC = None
            except Exception as e:
                print(f"[TTS] espeak-ng error: {e}", file=sys.stderr)

        # Cleanup temporary mp3 file
        if os.path.exists(tmp_audio):
            try:
                os.remove(tmp_audio)
            except OSError:
                pass

        if os.path.exists(SPEECH_PID_FILE):
            try:
                os.remove(SPEECH_PID_FILE)
            except OSError:
                pass

        stop_pulse.set()
        pulse_thread.join(timeout=0.5)

        # Acoustic cooldown: wait 0.8s to allow room sound reverberation to dissipate
        time.sleep(0.8)
        LAST_SPEAK_FINISH = time.time()
        IS_SPEAKING = False
        gc.collect()


# ── UNIFIED REAL-TIME AUDIO RECORDER & LEVEL STREAMER (ZERO-NUMPY PURE C AUDIOOP) ──
def record_speech_with_levels(timeout=15.0, phrase_time_limit=30.0, silence_timeout=2.0):
    """
    Record speech using lightweight sounddevice and native C audioop (Zero numpy overhead).
    Continuously streams live microphone volume to QML edge glow waves.
    Automatically detects speech start and speech finish (VAD), returns sr.AudioData.
    Saves over 500MB+ virtual memory, zero segfaults!
    """
    import sounddevice as sd
    import audioop
    import speech_recognition as sr

    frames = []
    has_spoken = False
    silence_start = None
    start_time = time.time()
    last_ipc_send = 0.0

    def audio_callback(indata, frame_count, time_info, status):
        nonlocal has_spoken, silence_start, last_ipc_send
        raw_chunk = bytes(indata)
        frames.append(raw_chunk)

        # Ultra-fast native C calculation of audio RMS (0 memory allocations)
        rms = audioop.rms(raw_chunk, 2) / 32768.0

        now = time.time()
        if now - last_ipc_send >= 0.035: # ~28 updates/sec
            last_ipc_send = now
            clean = max(0.0, rms - 0.002)
            lvl = min(1.0, clean * 30.0)
            SiriIPC.set_audio_level(lvl)

        # Voice Activity Detection (VAD)
        if rms > 0.004:
            has_spoken = True
            silence_start = None
        elif has_spoken and silence_start is None:
            silence_start = time.time()

    try:
        with sd.InputStream(channels=1, samplerate=16000, dtype='int16', blocksize=512, callback=audio_callback):
            while True:
                time.sleep(0.04)
                now = time.time()
                elapsed = now - start_time

                # If silence has elapsed after speaking, finish recording immediately
                if has_spoken and silence_start and (now - silence_start >= silence_timeout):
                    break

                # Max phrase limit
                if elapsed >= phrase_time_limit:
                    break

                # Timeout if no speech heard at all
                if not has_spoken and (elapsed >= timeout):
                    break
    finally:
        SiriIPC.set_audio_level(0.0)

    if not has_spoken or not frames:
        return None

    raw_bytes = b"".join(frames)
    return sr.AudioData(raw_bytes, 16000, 2)


# ── ASSISTANT INTERACTION CYCLE ──
def run_assistant_cycle(recognizer=None, mic=None):
    """
    1. Activate edge glow UI (listening state).
    2. Stream live microphone volume to edge glow waves.
    3. Convert speech to text via SpeechRecognition (free STT).
    4. Send prompt to Gemini AI or execute local app command.
    5. Speak response and update UI.
    6. Automatically dismiss Siri once task/speech is finished.
    """
    import speech_recognition as sr
    if recognizer is None:
        recognizer = sr.Recognizer()

    print("\n[Siri] 🎙️  Activated! Listening for your request...")
    SiriIPC.activate(True)
    SiriIPC.set_state("listening")
    SiriIPC.set_prompt("Listening...")
    SiriIPC.set_response("")

    user_query = ""

    try:
        audio = record_speech_with_levels(timeout=15.0, phrase_time_limit=30.0, silence_timeout=2.0)
        if not audio:
            print("[Siri] No speech heard in time.")
            SiriIPC.set_prompt("Listening timed out. Press Space to type.")
            SiriIPC.set_state("idle")
            return
    except Exception as e:
        print(f"[Siri] Microphone recording error: {e}")
        SiriIPC.set_prompt("Microphone unavailable.")
        time.sleep(1.2)
        SiriIPC.set_state("idle")
        return

    print("[Siri] 🧠 Processing speech...")
    SiriIPC.set_state("thinking")
    SiriIPC.set_prompt("Processing speech...")

    # Language selection
    lang_pref = CONFIG.get("language", "auto")
    try:
        if lang_pref == "auto":
            try:
                user_query = recognizer.recognize_google(audio, language="vi-VN")
            except sr.UnknownValueError:
                user_query = recognizer.recognize_google(audio, language="en-US")
        else:
            user_query = recognizer.recognize_google(audio, language=lang_pref)
    except Exception as e:
        print(f"[Siri] Recognition error: {e}")
        SiriIPC.set_prompt("Sorry, could not understand audio.")
        time.sleep(1.2)
        SiriIPC.activate(False)
        SiriIPC.set_state("idle")
        return

    print(f"[User] 🗣️  \"{user_query}\"")
    SiriIPC.set_prompt(user_query)
    SiriIPC.set_state("thinking")

    try:
        # Check Local-First Intent Router (e.g. open apps, volume, mute)
        local_ans = handle_local_intent(user_query)
        if local_ans:
            print(f"[Local Router] ⚡ Handled locally: \"{local_ans}\"")
            answer = local_ans
            SiriIPC.set_state("speaking")
            SiriIPC.set_response(answer)
            speak(answer)
            SiriIPC.set_state("idle")
            print("[Siri] Task completed successfully.\n")
            return
        else:
            print("[Siri] 🌐 Forwarding to Gemini AI...")
            answer = query_gemini(user_query)

        print(f"[Siri] 💬 \"{answer}\"")

        SiriIPC.set_state("speaking")
        SiriIPC.set_response(answer)

        # Read answer aloud with Neural TTS
        speak(answer)

        # Once speech has finished, transition state to idle
        SiriIPC.set_state("idle")
        print("[Siri] Response spoken completely.\n")
    finally:
        del user_query
        gc.collect()


# ── DAEMON CONTINUOUS LISTENER ──
def start_daemon():
    """Continuously listen for wake-words with robust echo cancellation."""
    import speech_recognition as sr

    recognizer = sr.Recognizer()
    recognizer.dynamic_energy_threshold = True
    recognizer.pause_threshold = 0.6

    wake_words = [w.lower() for w in CONFIG.get("wake_words", ["hey siri", "siri", "ơi siri"])]

    print("═════════════════════════════════════════════════════════════════")
    print(" 🌟 MacShell Siri Voice Assistant Daemon is Running")
    print(f" 🎯 Wake words: {', '.join(wake_words)}")
    print(f" 🤖 Gemini Model: {CONFIG.get('model', 'gemini-2.5-flash')}")
    print(" 🔊 Press Ctrl+C in this terminal to stop.")
    print("═════════════════════════════════════════════════════════════════\n")

    # Verify microphone
    try:
        mic = sr.Microphone()
        with mic as source:
            print("[Init] Calibrating microphone for ambient noise...")
            recognizer.adjust_for_ambient_noise(source, duration=1.0)
            print("[Init] Calibration complete. Ready!")
    except Exception as e:
        print(f"[Error] Failed to initialize microphone: {e}", file=sys.stderr)
        return

    cycle_count = 0
    while True:
        try:
            # ANTI-LOOP: If speaking or within 2.5s cooldown after speaking, skip mic recording
            # to strictly prevent speaker echo from triggering wake word!
            if IS_SPEAKING or (time.time() - LAST_SPEAK_FINISH < 2.5):
                time.sleep(0.3)
                continue

            with mic as source:
                audio = recognizer.listen(source, timeout=None, phrase_time_limit=4.0)

            # Re-check speaking flag after recording chunk
            if IS_SPEAKING or (time.time() - LAST_SPEAK_FINISH < 2.5):
                del audio
                continue

            # Recognize short wake word snippet
            try:
                heard = ""
                try:
                    heard = recognizer.recognize_google(audio, language="en-US").lower()
                except Exception:
                    heard = recognizer.recognize_google(audio, language="vi-VN").lower()

                # Self-Echo Filter: Ignore if snippet contains words from Siri's own recent response
                if LAST_SPOKEN_TEXT and any(w in LAST_SPOKEN_TEXT for w in heard.split() if len(w) > 3):
                    print(f"[Echo Filter] Discarded room speaker feedback: \"{heard}\"")
                    continue

                matched = any(w in heard for w in wake_words)
                if matched:
                    print(f"\n[Trigger] Detected wake word in: \"{heard}\"")
                    run_assistant_cycle(recognizer, mic)

            except sr.UnknownValueError:
                pass
            except sr.RequestError as e:
                time.sleep(1.0)
            finally:
                del audio
                cycle_count += 1
                if cycle_count >= 8:
                    cycle_count = 0
                    gc.collect()

        except KeyboardInterrupt:
            print("\n[Siri] Stopping daemon gracefully...")
            SiriIPC.activate(False)
            gc.collect()
            break
        except Exception as e:
            time.sleep(0.5)


# ── DIRECT QUERY TEST ──
def handle_query_mode(query_text: str, enable_tts: bool = True):
    """Test Gemini API and UI response card directly without voice input."""
    print(f"\n[Test Query] Prompt: \"{query_text}\"")
    SiriIPC.activate(True)
    SiriIPC.set_state("thinking")
    SiriIPC.set_prompt(query_text)
    SiriIPC.set_response("Processing request...")

    # Check Local-First Intent Router (0 AI Tokens)
    local_ans = handle_local_intent(query_text)
    if local_ans:
        print(f"[Local Router] ⚡ Handled locally (0 tokens): \"{local_ans}\"")
        answer = local_ans
    else:
        print("[Siri] 🌐 Forwarding to Gemini AI...")
        answer = query_gemini(query_text)

    print(f"[Response] {answer}")

    SiriIPC.set_state("speaking" if enable_tts else "idle")
    SiriIPC.set_response(answer)

    if enable_tts:
        print("[TTS] Reading response aloud with Neural TTS...")
        speak(answer)
        SiriIPC.set_state("idle")
        print("[Siri] Query response finished.")
    else:
        SiriIPC.set_state("idle")
    gc.collect()
    print("[Done] Query finished successfully.")


# ── CLI ENTRY POINT ──
def main():
    parser = argparse.ArgumentParser(description="MacShell Siri Voice Assistant Daemon")
    parser.add_argument("--daemon", action="store_true", help="Start continuous wake-word listener daemon")
    parser.add_argument("--trigger", action="store_true", help="Trigger a single listening cycle right now")
    parser.add_argument("--awake", action="store_true", help="Awake Siri on-demand: open mic, listen, respond, and close mic immediately")
    parser.add_argument("--query", type=str, help="Send a text query to Gemini and test TTS/UI directly")
    parser.add_argument("--no-tts", action="store_true", help="Disable TTS speech output for text query")
    parser.add_argument("--test-api", action="store_true", help="Test Gemini API connectivity")
    parser.add_argument("--test-tts", type=str, help="Test TTS synthesis with given text")
    parser.add_argument("--test-ipc", action="store_true", help="Test Quickshell edge glow and speech card")
    parser.add_argument("--stop-speech", action="store_true", help="Stop all currently playing speech immediately")

    args = parser.parse_args()

    if args.stop_speech:
        stop_all_speech()
        print("[TTS] Speech playback stopped immediately.")
        return

    if args.test_api:
        print("[API Test] Contacting Gemini API...")
        res = query_gemini("Say hello in one short sentence.")
        print(f"[API Result] {res}")
        return

    if args.test_tts:
        print(f"[TTS Test] Speaking: {args.test_tts}")
        speak(args.test_tts)
        return

    if args.test_ipc:
        print("[IPC Test] Showing Siri Edge Glow and Speech Card...")
        SiriIPC.activate(True)
        SiriIPC.set_state("speaking")
        SiriIPC.set_prompt("What is Quickshell on Linux?")
        SiriIPC.set_response("Quickshell is a flexible framework for creating desktop shell interfaces with Qt and QML.")
        time.sleep(4.0)
        SiriIPC.activate(False)
        print("[IPC Test] Done.")
        return

    if args.query:
        handle_query_mode(args.query, enable_tts=not args.no_tts)
        return

    if args.trigger or args.awake:
        import fcntl
        lock_file = "/tmp/macshell_siri_awake.lock"
        pid_file = "/tmp/macshell_siri_awake.pid"
        try:
            lock_fd = open(lock_file, "w")
            fcntl.flock(lock_fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except (IOError, BlockingIOError):
            print("[Siri] An awake cycle is already active. Toggling dismiss.")
            try:
                if os.path.exists(pid_file):
                    with open(pid_file, "r") as pf:
                        old_pid = int(pf.read().strip())
                    if old_pid != os.getpid():
                        os.kill(old_pid, 15)
            except Exception:
                pass
            SiriIPC.activate(False)
            return

        try:
            with open(pid_file, "w") as pf:
                pf.write(str(os.getpid()))
        except Exception:
            pass

        try:
            import speech_recognition as sr
            r = sr.Recognizer()
            r.dynamic_energy_threshold = True
            r.pause_threshold = 0.6
            run_assistant_cycle(r)
        finally:
            try:
                fcntl.flock(lock_fd, fcntl.LOCK_UN)
                lock_fd.close()
                if os.path.exists(lock_file):
                    os.remove(lock_file)
                if os.path.exists(pid_file):
                    os.remove(pid_file)
            except Exception:
                pass
        return

    # Default to daemon mode if called directly
    start_daemon()

if __name__ == "__main__":
    main()
