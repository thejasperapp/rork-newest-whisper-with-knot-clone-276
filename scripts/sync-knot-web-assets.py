"""Copy the registered iOS Knot artwork into versioned web runtime assets."""
from pathlib import Path
import shutil

root = Path(__file__).resolve().parents[1]
source = root / 'ios/Whisper/WhisperFitnessApp/Assets.xcassets'
target = root / 'web-whisperweb/public/knot-native-20261030'
target.mkdir(parents=True, exist_ok=True)
assets = {
    'KnotNeutralV2/knot-mascot-assembled-v2': 'neutral',
    'KnotTorso/knot-knit-torso': 'torso',
    'KnotHandLeft/knot-knit-hand-left': 'hand-left',
    'KnotHandRight/knot-knit-hand-right': 'hand-right',
    'KnotEyeLeft/jasper-eye-left': 'eye-left',
    'KnotEyeRight/jasper-eye-right': 'eye-right',
    'KnotOrb/orb': 'orb',
    'KnotWordmark/knot-wordmark-black': 'wordmark-black',
    'KnotWordmark/knot-wordmark-white': 'wordmark-white',
}
for key, name in assets.items():
    folder, filename = key.split('/')
    shutil.copyfile(source / f'{folder}.imageset' / f'{filename}.png', target / f'{name}.png')
print(f'Synced {len(assets)} original Knot assets.')
