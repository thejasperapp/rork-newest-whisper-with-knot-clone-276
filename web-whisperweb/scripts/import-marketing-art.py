"""Import only presentation artwork from the supplied Workspace source ZIP.
Usage: python scripts/import-marketing-art.py /path/to/extracted/public
Original pixels are resized for web delivery; no app/backend code is imported.
"""
from pathlib import Path
import sys
from PIL import Image

source = Path(sys.argv[1])
target = Path(__file__).resolve().parent.parent / 'public' / 'marketing-20261029'
names = [
    f'{stem}-{mode}-20260925.png'
    for stem in ('workspace-w', 'workspace-notes', 'meet-icon',
                 'workspace-studio', 'workspace-teams', 'workspace-recruiters')
    for mode in ('light', 'dark')
] + [f'knot-20261026/{name}.png' for name in (
    'knot-mascot-assembled-v2', 'knot-wordmark-black', 'knot-wordmark-white')]
for name in names:
    image = Image.open(source / name).convert('RGBA')
    image.thumbnail((640, 640), Image.Resampling.LANCZOS)
    output = target / Path(name).with_suffix('.webp')
    output.parent.mkdir(parents=True, exist_ok=True)
    image.save(output, 'WEBP', quality=88, method=6)
print(f'Imported and optimized {len(names)} supplied assets.')
