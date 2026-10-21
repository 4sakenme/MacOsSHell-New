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


# ── SYSTEM CONTROL TOOLS (GEMINI FUNCTION CALLING) ──
def launch_app(app_name: str) -> str:
    """Launch an application on Linux by its name or command (e.g. firefox, kitty, spotify, code, dolphin)."""
    clean_name = app_name.strip().lower()
    try:
        if os.getenv("HYPRLAND_INSTANCE_SIGNATURE"):
            subprocess.run(["hyprctl", "dispatch", "exec", clean_name], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            return f"Successfully launched {app_name}."
    except Exception:
        pass

    try:
        subprocess.Popen([clean_name], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)
        return f"Successfully launched {app_name}."
    except Exception as e:
        try:
            subprocess.run(["gtk-launch", clean_name], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            return f"Launched {app_name} with gtk-launch."
        except Exception:
            return f"Could not launch {app_name}: {e}"

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

def get_weather(location: str) -> str:
    """Get real-time weather information for a given city or location without API keys."""
    import unicodedata
    clean_loc = "".join(c for c in unicodedata.normalize("NFD", location.strip()) if unicodedata.category(c) != "Mn").replace("đ", "d").replace("Đ", "D")
    loc_param = clean_loc.replace(" ", "+")
    try:
        req = urllib.request.Request(f"https://wttr.in/{loc_param}?format=3", headers={"User-Agent": "curl/8.0"})
        with urllib.request.urlopen(req, timeout=4) as resp:
            data = resp.read().decode("utf-8").strip()
            if data and not data.startswith("<"):
                return data
    except Exception as e:
        return f"Could not retrieve weather for {location}: {e}"
    return f"Weather for {location} is currently unavailable."

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
    Returns response string if handled, or None to fallback to Gemini AI.
    """
    raw_q = query.strip()
    norm_q = normalize_text(raw_q)
    if not norm_q:
        return None

    # 1. THỜI TIẾT (Weather API)
    weather_keywords = ["thoi tiet", "nhiet do", "weather"]
    if any(k in norm_q for k in weather_keywords):
        loc = "Danang"
        m = re.search(r'(?:thoi tiet|nhiet do|weather)(?:\s+(?:tai|o|in|cua|tai tinh|tp))?\s+([a-zA-Z0-9\s]+)', norm_q)
        if m and m.group(1).strip():
            candidate = m.group(1).strip()
            candidate = re.sub(r'\b(hom nay|ngay mai|the nao|ra sao|bay gio|today|now)\b', '', candidate).strip()
            if candidate:
                loc = candidate
        try:
            loc_param = loc.replace(" ", "+")
            req = urllib.request.Request(f"https://wttr.in/{loc_param}?format=3", headers={"User-Agent": "curl/8.0"})
            with urllib.request.urlopen(req, timeout=3.5) as resp:
                data = resp.read().decode("utf-8").strip()
                if data and not data.startswith("<"):
                    return f"Thời tiết tại {loc.title()}: {data}"
        except Exception:
            pass
        return f"Hiện tại không thể lấy dữ liệu thời tiết cho {loc.title()}."

    # 2. MỞ NHẠC (Music Playback)
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

    # 3. TÌM KIẾM GOOGLE (Web Search)
    search_keywords = ["tim kiem", "search", "google"]
    for sk in search_keywords:
        if norm_q.startswith(sk):
            term = re.sub(rf'^{sk}\s*', '', raw_q).strip()
            if term:
                open_url(f"https://www.google.com/search?q={urllib.parse.quote(term)}")
                return f"Đang tìm kiếm '{term}' trên Google cho bạn."

    # 4. MỞ ỨNG DỤNG (Launch App)
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

    # 5. TÌM FILE (Search Files)
    file_keywords = ["tim file", "tim tep", "tim tap tin", "search file", "find file"]
    for fk in file_keywords:
        if fk in norm_q:
            kw = re.sub(rf'^.*?{fk}\s*', '', norm_q).strip()
            if kw:
                return search_files(kw)

    # Fallback to Gemini AI for reasoning, code, translation, etc.
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
        "Use available tools when asked to launch apps, open URLs, play music, check weather, or search files. "
        "Do not use markdown bolding or bullets because your reply will be read aloud."
    )

    from google import genai
    from google.genai import types

    client = genai.Client(api_key=api_key)
    config = types.GenerateContentConfig(
        system_instruction=system_instruction,
        tools=[launch_app, open_url, play_music, get_weather, search_files],
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


# ── TEXT TO SPEECH (TTS) ──
def is_vietnamese(text: str) -> bool:
    """Check if the response contains Vietnamese characters."""
    return bool(re.search(r'[àáạảãâầấậẩẫăằắặẳẵèéẹẻẽêềếệểễìíịỉĩòóọỏõôồốộổỗơờớợởỡùúụủũưừứựửữỳýỵỷỹđ]', text, re.IGNORECASE))

def speak(text: str):
    """Read text aloud with audio level pulsing."""
    clean_text = re.sub(r'[*_#`~]', '', text).strip()
    if not clean_text:
        return

    # Choose voice based on language
    if is_vietnamese(clean_text):
        voice = CONFIG.get("tts_voice_vi", "vi")
    else:
        voice = CONFIG.get("tts_voice_en", "en-us+f3")

    rate = str(CONFIG.get("speech_rate", 165))

    # Pulsing thread while TTS is running (bounded memory queue)
    stop_pulse = threading.Event()
    level_queue = deque([0.35, 0.65, 0.85, 0.55, 0.75, 0.45, 0.90, 0.60], maxlen=16)

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

    try:
        subprocess.run(
            ["espeak-ng", "-v", voice, "-s", rate, clean_text],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL
        )
    except FileNotFoundError:
        print("[TTS] espeak-ng not found. Please install espeak-ng.", file=sys.stderr)
    finally:
        stop_pulse.set()
        pulse_thread.join(timeout=0.5)
        del level_queue
        gc.collect()


# ── ASSISTANT INTERACTION CYCLE ──
def run_assistant_cycle(recognizer, mic=None):
    """
    1. Activate edge glow UI (listening state).
    2. Record user speech from microphone.
    3. Convert to text via SpeechRecognition (free STT).
    4. Send prompt to Gemini API (thinking state).
    5. Speak response and update UI (speaking state).
    6. Return to idle and auto-dismiss.
    """
    import speech_recognition as sr

    print("\n[Siri] 🎙️  Activated! Listening for your request...")
    SiriIPC.activate(True)
    SiriIPC.set_state("listening")
    SiriIPC.set_prompt("Listening...")
    SiriIPC.set_response("")

    user_query = ""

    try:
        with (mic if mic else sr.Microphone()) as source:
            recognizer.adjust_for_ambient_noise(source, duration=0.4)
            # Listen with a 6-second phrase limit
            audio = recognizer.listen(source, timeout=5.0, phrase_time_limit=10.0)

        print("[Siri] 🧠 Processing speech...")
        SiriIPC.set_state("thinking")
        SiriIPC.set_prompt("Processing speech...")

        # Language selection
        lang_pref = CONFIG.get("language", "auto")
        if lang_pref == "auto":
            # Try English first, fallback or recognize bilingual
            try:
                user_query = recognizer.recognize_google(audio, language="vi-VN")
            except sr.UnknownValueError:
                user_query = recognizer.recognize_google(audio, language="en-US")
        else:
            user_query = recognizer.recognize_google(audio, language=lang_pref)

    except sr.WaitTimeoutError:
        print("[Siri] No speech heard in time.")
        SiriIPC.set_prompt("I didn't hear anything.")
        time.sleep(1.5)
        SiriIPC.activate(False)
        return
    except sr.UnknownValueError:
        print("[Siri] Could not understand audio.")
        SiriIPC.set_prompt("Sorry, I didn't catch that.")
        time.sleep(1.5)
        SiriIPC.activate(False)
        return
    except Exception as e:
        print(f"[Siri] Speech recognition error: {e}")
        SiriIPC.set_prompt("Speech recognition unavailable.")
        time.sleep(1.5)
        SiriIPC.activate(False)
        return

    print(f"[User] 🗣️  \"{user_query}\"")
    SiriIPC.set_prompt(user_query)
    SiriIPC.set_state("thinking")

    try:
        # Check Local-First Intent Router (0 AI Tokens)
        local_ans = handle_local_intent(user_query)
        if local_ans:
            print(f"[Local Router] ⚡ Handled locally (0 tokens): \"{local_ans}\"")
            answer = local_ans
        else:
            print("[Siri] 🌐 Forwarding to Gemini AI...")
            answer = query_gemini(user_query)
        print(f"[Siri] 💬 \"{answer}\"")

        SiriIPC.set_state("speaking")
        SiriIPC.set_response(answer)

        # Read answer aloud
        speak(answer)

        # Cooldown & dismiss
        time.sleep(1.5)
        SiriIPC.activate(False)
        SiriIPC.set_state("idle")
        print("[Siri] Cycle completed. Returning to idle.\n")
    finally:
        # Strict memory cleanup after each cycle
        del user_query
        gc.collect()


# ── DAEMON CONTINUOUS LISTENER ──
def start_daemon():
    """Continuously listen for wake-words ("Hey Siri", "Siri")."""
    import speech_recognition as sr

    recognizer = sr.Recognizer()
    recognizer.dynamic_energy_threshold = True
    recognizer.pause_threshold = 0.6

    wake_words = [w.lower() for w in CONFIG.get("wake_words", ["hey siri", "siri", "ơi siri"])]

    print("═════════════════════════════════════════════════════════════════")
    print(" 🌟 MacShell Siri Voice Assistant Daemon is Running")
    print(f" 🎯 Wake words: {', '.join(wake_words)}")
    print(f" 🤖 Gemini Model: {CONFIG.get('model', 'gemini-1.5-flash')}")
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
            with mic as source:
                # Fast listening for potential wake words
                audio = recognizer.listen(source, timeout=None, phrase_time_limit=4.0)

            # Recognize short wake word snippet
            try:
                # Fast check in English and Vietnamese
                heard = ""
                try:
                    heard = recognizer.recognize_google(audio, language="en-US").lower()
                except Exception:
                    heard = recognizer.recognize_google(audio, language="vi-VN").lower()

                matched = any(w in heard for w in wake_words)
                if matched:
                    print(f"\n[Trigger] Detected wake word in: \"{heard}\"")
                    run_assistant_cycle(recognizer, mic)

            except sr.UnknownValueError:
                pass
            except sr.RequestError as e:
                time.sleep(1.0)
            finally:
                # Discard audio chunk immediately
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
        print("[TTS] Reading response aloud...")
        speak(answer)
        print("[IPC] Waiting 3s before auto-dismiss...")
        time.sleep(3.0)
        SiriIPC.activate(False)
        SiriIPC.set_state("idle")
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

    args = parser.parse_args()

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
        import speech_recognition as sr
        r = sr.Recognizer()
        r.dynamic_energy_threshold = True
        r.pause_threshold = 0.6
        run_assistant_cycle(r)
        return

    # Default to daemon mode if called directly
    start_daemon()

if __name__ == "__main__":
    main()
