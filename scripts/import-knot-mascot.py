"""Import original Knot v2 artwork and verify neutral assembly pixel-for-pixel.
Usage: python3 scripts/import-knot-mascot.py /path/to/knot-mascot-handoff-v2.zip
Requires Pillow for the supplied reference's assembly comparison.
"""
import json
import sys
from io import BytesIO
from pathlib import Path
from zipfile import ZipFile
from PIL import Image, ImageChops

ROOT = Path(__file__).resolve().parents[1]
CATALOG = ROOT / "ios/Whisper/WhisperFitnessApp/Assets.xcassets"
LAYERS = {
    "knot-knit-torso.png": "KnotTorso",
    "knot-knit-hand-left.png": "KnotHandLeft",
    "knot-knit-hand-right.png": "KnotHandRight",
    "jasper-eye-left.png": "KnotEyeLeft",
    "jasper-eye-right.png": "KnotEyeRight",
    "orb.png": "KnotOrb",
}

with ZipFile(sys.argv[1]) as archive:
    # Explicit allowlist; no archive-controlled filesystem paths or executable code.
    payloads = {source: archive.read(f"knot-mascot/layers/{source}") for source in LAYERS}
    finished_name = "knot-mascot-assembled-v2.png"
    finished = archive.read(f"knot-mascot/{finished_name}")
    images = {name: Image.open(BytesIO(data)).convert("RGBA") for name, data in payloads.items()}
    assert all(image.size == (647, 647) for name, image in images.items() if name.startswith("knot-knit-"))
    assert images["jasper-eye-left.png"].size == (134, 221)
    assert images["jasper-eye-right.png"].size == (131, 222)
    neutral = Image.new("RGBA", (647, 647))
    for name in ["knot-knit-hand-right.png", "knot-knit-hand-left.png", "knot-knit-torso.png"]:
        neutral.alpha_composite(images[name])
    neutral.alpha_composite(images["jasper-eye-left.png"], (173, 138))
    neutral.alpha_composite(images["jasper-eye-right.png"], (344, 138))
    reference = Image.open(BytesIO(finished)).convert("RGBA")
    assert reference.size == neutral.size
    assert all(channel.getbbox() is None for channel in ImageChops.difference(neutral, reference).split()), "Neutral assembly differs from supplied v2 reference"
    print("Neutral 647 x 647 assembly: exact RGBA pixel match with supplied v2 PNG")
    payloads[finished_name] = finished
    names = dict(LAYERS, **{finished_name: "KnotNeutralV2"})
    for source, name in names.items():
        data = payloads[source]
        if not data.startswith(b"\x89PNG\r\n\x1a\n"):
            raise ValueError(f"Expected PNG: {source}")
        folder = CATALOG / f"{name}.imageset"
        folder.mkdir(parents=True, exist_ok=True)
        (folder / source).write_bytes(data)
        (folder / "Contents.json").write_text(json.dumps({
            "images": [{"filename": source, "idiom": "universal"}],
            "info": {"author": "xcode", "version": 1},
            "properties": {"template-rendering-intent": "original"}
        }, indent=2) + "\n")
        print(f"Imported {name}: {len(data)} original bytes")
