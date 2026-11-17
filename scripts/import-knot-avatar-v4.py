"""Import November 15 supplied masters without resizing or re-encoding video.
Usage: python3 scripts/import-knot-avatar-v4.py <extracted-kit>
"""
from pathlib import Path
import sys, shutil, json
from PIL import Image
root = Path(__file__).resolve().parents[1]
kit = Path(sys.argv[1])
target = root / 'ios/Whisper/WhisperFitnessApp/Resources/KnotAvatarV4'
target.mkdir(parents=True, exist_ok=True)
for source in (kit / 'animations').glob('*.mp4'):
    shutil.copy2(source, target / source.name)
if (kit / 'dance-6.mp4').exists():
    shutil.copy2(kit / 'dance-6.mp4', target / 'dance-6.mp4')
assets = root / 'ios/Whisper/WhisperFitnessApp/Assets.xcassets'
# Resolve the actual owning target's catalog rather than creating another one.
if not assets.exists():
    assets = next((root / 'ios/Whisper').rglob('Assets.xcassets'))
for source in (kit / 'stills').glob('*.webp'):
    shutil.copy2(source, target / source.name)
    name = 'KnotV4-' + source.stem.removeprefix('knot-avatar').lstrip('-')
    if name == 'KnotV4-': name = 'KnotV4-master'
    folder = assets / (name + '.imageset')
    folder.mkdir(parents=True, exist_ok=True)
    Image.open(source).convert('RGBA').save(folder / 'poster.png')
    (folder / 'Contents.json').write_text(json.dumps({'images': [{'filename': 'poster.png', 'idiom': 'universal'}], 'info': {'author': 'xcode', 'version': 1}}, indent=2) + '\n')
print('Imported original five state clips, available dance, seven masters and lossless native posters.')
