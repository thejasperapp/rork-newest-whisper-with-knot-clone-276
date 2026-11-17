"""Prepare the supplied November avatar as independently animated native layers.
Requires Pillow, numpy and scipy. Keeps the supplied yarn pixels, lifts the
background, and separates eyes; the Swift renderer owns all motion (no video).
"""
from pathlib import Path
import json
import math
import numpy as np
from PIL import Image, ImageDraw, ImageFilter
from scipy import ndimage

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'assets/knot-avatar-v3/reference-light.webp'
DEST = ROOT / 'ios/Whisper/WhisperFitnessApp/Assets.xcassets'
image = Image.open(SOURCE).convert('RGB')
rgb = np.array(image)
# The dark yarn is unambiguous against both the white ground and amber halo.
labels, _ = ndimage.label(rgb.max(axis=2) < 125)
counts = np.bincount(labels.ravel()); counts[0] = 0
silhouette = ndimage.binary_fill_holes(ndimage.binary_closing(labels == counts.argmax(), iterations=3))
alpha = Image.fromarray((silhouette * 255).astype('uint8')).filter(ImageFilter.GaussianBlur(.65))
CROP = (256, 300, 1344, 1388)

def save(name, value, full=True):
    if full:
        value = value.crop(CROP).resize((768, 768), Image.Resampling.LANCZOS)
    path = DEST / (name + '.imageset')
    path.mkdir(parents=True, exist_ok=True)
    value.save(path / 'artwork.png', optimize=True)
    (path / 'Contents.json').write_text(json.dumps({'images': [{'filename': 'artwork.png', 'idiom': 'universal'}], 'info': {'author': 'xcode', 'version': 1}}, indent=2) + '\n')

neutral = image.convert('RGBA'); neutral.putalpha(alpha)
save('KnotNeutralV3', neutral)
torso = image.copy()
for name, box in [('KnotEyeLeftV3', (520, 510, 795, 925)), ('KnotEyeRightV3', (810, 510, 1085, 925))]:
    region = image.crop(box)
    pixels = np.array(region)
    warm = (pixels[:,:,0] > 150) & (pixels[:,:,1] > 60) & (pixels[:,:,2] < 180)
    warm = ndimage.binary_fill_holes(warm)
    mask = Image.fromarray((warm * 255).astype('uint8')).filter(ImageFilter.GaussianBlur(.7))
    eye = region.convert('RGBA'); eye.putalpha(mask)
    registered = Image.new('RGBA', image.size)
    registered.paste(eye, box[:2])
    save(name, registered)
    # Reconstruct hidden yarn using the same vertical stitch column below.
    stitches = np.array(image.crop((box[0], 915, box[2], 1125)))
    patch = Image.fromarray(np.tile(stitches, (2, 1, 1))[:region.height])
    repair = Image.fromarray((ndimage.binary_dilation(warm, iterations=24) * 255).astype('uint8')).filter(ImageFilter.GaussianBlur(5))
    torso.paste(patch, box[:2], repair)
torso = torso.convert('RGBA'); torso.putalpha(alpha)
save('KnotBodyV3', torso)
# A real yarn-textured star, not an icon pasted over the character.
star_size = 384
texture = image.crop((600, 920, 1000, 1320)).resize((star_size, star_size), Image.Resampling.LANCZOS).convert('RGBA')
mask = Image.new('L', (star_size, star_size)); draw = ImageDraw.Draw(mask)
points = []
for i in range(10):
    a = -math.pi / 2 + i * math.pi / 5
    r = 172 if i % 2 == 0 else 86
    points.append((192 + math.cos(a) * r, 192 + math.sin(a) * r))
draw.polygon(points, fill=255)
mask = mask.filter(ImageFilter.GaussianBlur(3))
texture.putalpha(mask)
save('KnotMilestoneStarV3', texture, full=False)
print('Prepared native body, independent registered eyes, neutral pose and yarn star.')
