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
import json
import time
import argparse
import subprocess
import threading
import re
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
    if CONFIG_FILE.exists():
        try:
            with open(CONFIG_FILE, "r", encoding="utf-8") as f:
                user_conf = json.load(f)
                config.update(user_conf)
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


# ── GEMINI API INTEGRATION ──
def query_gemini(prompt: str) -> str:
    """Send question to Gemini model and return text response."""
    api_key = CONFIG.get("api_key", "").strip()
    if not api_key or api_key == "YOUR_GEMINI_API_KEY_HERE":
        return "Please configure your Gemini API key in ~/.config/quickshell/MacShell/gemini_config.json."

    model_name = CONFIG.get("model", "gemini-1.5-flash")

    system_instruction = (
        "You are Siri, Apple's intelligent virtual assistant, integrated into MacShell on Linux. "
        "Keep your answers concise, direct, helpful, and natural for speech output. "
        "Do not use markdown formatting like bullet points or bold asterisks since your response will be read aloud."
    )

    full_prompt = f"{system_instruction}\n\nUser: {prompt}\nSiri:"

    # Try modern google-genai SDK first
    try:
        from google import genai
        client = genai.Client(api_key=api_key)
        response = client.models.generate_content(
            model=model_name,
            contents=full_prompt
        )
        if response and response.text:
            return response.text.strip()
    except Exception as e:
        # Fallback to legacy google.generativeai if available
        try:
            import google.generativeai as legacy_genai
            legacy_genai.configure(api_key=api_key)
            model = legacy_genai.GenerativeModel(model_name)
            response = model.generate_content(full_prompt)
            if response and response.text:
                return response.text.strip()
        except Exception as e2:
            return f"Error contacting Gemini: {e}"

    return "I'm sorry, I couldn't get a response right now."


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

    # Pulsing thread while TTS is running
    stop_pulse = threading.Event()

    def pulse_loop():
        levels = [0.4, 0.75, 0.9, 0.6, 0.85, 0.5, 0.95, 0.7]
        idx = 0
        while not stop_pulse.is_set():
            SiriIPC.set_audio_level(levels[idx % len(levels)])
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

    # Ask Gemini
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

        except KeyboardInterrupt:
            print("\n[Siri] Stopping daemon gracefully...")
            SiriIPC.activate(False)
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
    SiriIPC.set_response("Connecting to Gemini...")

    answer = query_gemini(query_text)
    print(f"[Gemini Response] {answer}")

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

    if args.trigger:
        import speech_recognition as sr
        r = sr.Recognizer()
        run_assistant_cycle(r)
        return

    # Default to daemon mode if called directly
    start_daemon()

if __name__ == "__main__":
    main()
