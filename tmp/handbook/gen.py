#!/usr/bin/env python3
"""Generate the Whisper Handbook storytime audio: 13 narration clips in
Jasper's realtime `echo` voice + 4 real-book SFX. Batched so each bash call
stays under the 60s limit: `gen.py a` (clips 0-6), `gen.py b` (7-12),
`gen.py sfx`."""
import base64
import json
import os
import sys
import urllib.error
import urllib.request

KEY = "rork_sk_ena9h145pd1xthwtg592e0wwq53nwtg7"
DIR = os.path.dirname(os.path.abspath(__file__))
MODEL_FILE = os.path.join(DIR, "model.txt")

CLIPS = [
    ("handbook_welcome", "Hey everyone — Jasper here. This is the Whisper Handbook: how this whole place works, in one short book. Thirteen pages, about four minutes. I'll turn the pages — you just relax."),
    ("handbook_noise", "Page one — why Whisper exists. The big feeds turned into malls. Bright, loud, and honestly? Kind of lonely. Everyone performing for a counter, and almost nobody saying anything real."),
    ("handbook_whisper", "But real advice never died. It just went quiet — locker rooms, group chats, five a.m. texts. Truth told quietly has a name: a whisper. That's the whole idea. This is a room, not a stage."),
    ("handbook_density", "One rule shapes everything here: density over reach. A hundred people who actually show up beat a million who scroll past. So we fill one small room wall to wall — and then we build the next one."),
    ("handbook_guilds_light", "Everyone on Whisper belongs to a guild. Creators make the things worth sharing. Coaches turn effort into progress. And athletes bring the proof — they do the work in public. Those three carry the light."),
    ("handbook_guilds_watch", "Four more guilds keep it honest. Recruiters open real doors. Brands fund the work — always labeled, never sneaky. Members are the heartbeat of every room. And keepers — the mods and admins — hold the standard so nobody else has to."),
    ("handbook_badge", "Badges here are earned. You apply, a real person reviews it, and once it's yours, everyone knows you're really you. A badge means one thing: this account is exactly who it says it is."),
    ("handbook_rules", "House rules, short version: be real, be useful, and never feed the trolls. Hard lines — harassment, hate, fake numbers — mean you're out. Everything else gets four fair steps: a warning, a strike, a timeout, and only then, the door."),
    ("handbook_quiz", "Okay, quick check — one question. What matters most on Whisper? Vote on your screen. I'll wait."),
    ("handbook_feed", "Here's the feed, with the real numbers. A post's energy halves about every twenty hours. A comment counts two and a half times a like. Voices you follow ring about one and a half times louder. Anything under ninety minutes gets a fresh boost. And you'll never see more than one ad in six posts. That's the whole formula."),
    ("handbook_gates", "Growth here is five gates. One hundred true fans. Then a thousand. Ten thousand. A hundred thousand. And gate five — a million. We pass them in order, together. Nobody skips."),
    ("handbook_oath", "Last page. The oath is one sentence: show up real, make it useful, and leave every room better than you found it. If that sounds like you, sign it — your name goes in the book, right here."),
    ("handbook_wrap", "And that's the Whisper Handbook. Thanks for reading it with me. I'm around whenever you need me — now go make something worth whispering about."),
]

SFX = [
    ("handbook_page", "A single soft paper page turn in a quiet room. Gentle, delicate, close-mic. No music, no voices.", 1.2),
    ("handbook_open", "A hardcover book opening gently: a soft leather flex and a light paper settle. Quiet, warm, close-mic. No music.", 1.6),
    ("handbook_close", "A hardcover book closing gently with a soft padded thump. Warm, quiet room. No music.", 1.4),
    ("handbook_chime", "A soft warm chime with a gentle magical sparkle tail. Short, pleasant, subtle, airy. No melody.", 2.2),
]


def model() -> str:
    try:
        with open(MODEL_FILE) as fh:
            return fh.read().strip() or "openai/tts-1-hd"
    except OSError:
        return "openai/tts-1-hd"


def tts(name: str, text: str) -> None:
    out = os.path.join(DIR, name + ".mp3")
    if os.path.exists(out) and os.path.getsize(out) > 4000:
        print("skip", name)
        return
    current = model()
    body = json.dumps({"text": text, "voice": "echo", "outputFormat": "mp3"}).encode()
    req = urllib.request.Request(
        "https://toolkit.rork.com/v2/vercel/v4/ai/speech-model",
        data=body,
        headers={
            "Authorization": "Bearer " + KEY,
            "Content-Type": "application/json",
            "ai-model-id": current,
            "ai-gateway-protocol-version": "0.0.1",
        },
    )
    try:
        with urllib.request.urlopen(req, timeout=35) as resp:
            data = json.loads(resp.read())
    except urllib.error.HTTPError as err:
        if current == "openai/tts-1-hd":
            with open(MODEL_FILE, "w") as fh:
                fh.write("openai/tts-1")
            print("hd unavailable (%s) -> tts-1" % err.code)
            tts(name, text)
            return
        raise
    with open(out, "wb") as fh:
        fh.write(base64.b64decode(data["audio"]))
    print("ok", name, current, os.path.getsize(out))


def sfx(name: str, prompt: str, seconds: float) -> None:
    out = os.path.join(DIR, name + ".mp3")
    if os.path.exists(out) and os.path.getsize(out) > 2000:
        print("skip", name)
        return
    body = json.dumps({"text": prompt, "duration_seconds": seconds}).encode()
    req = urllib.request.Request(
        "https://toolkit.rork.com/v2/elevenlabs/v1/sound-generation",
        data=body,
        headers={"Authorization": "Bearer " + KEY, "Content-Type": "application/json"},
    )
    with urllib.request.urlopen(req, timeout=45) as resp:
        blob = resp.read()
    with open(out, "wb") as fh:
        fh.write(blob)
    print("ok", name, len(blob))


which = sys.argv[1] if len(sys.argv) > 1 else "a"
if which == "a":
    for n, t in CLIPS[:7]:
        tts(n, t)
elif which == "b":
    for n, t in CLIPS[7:]:
        tts(n, t)
elif which == "sfx":
    for n, p, s in SFX:
        sfx(n, p, s)
print("done", which)
