"""Download this review's supplied references into ignored private review storage.
Only extraction metadata is printed. Videos/PDFs remain outside source control.
"""
import os
from pathlib import Path
import subprocess
import sys

root = Path(__file__).resolve().parents[1]
review = root / '.local/knot-references/experience-20261110'
review.mkdir(parents=True, exist_ok=True)
media = Path(os.environ['TMPDIR']) / 'knot-experience-20261110'
media.mkdir(parents=True, exist_ok=True)
attachments = [
    (media / 'reference.mp4', 'ibn3m7aus2fthnh8hdoi4.mp4'),
    (review / 'document-creation.md', 'wcdayd6bcbnu5m6504kw8.md'),
    (media / 'document-creation.pdf', '9h3ivftw8n2fgr4qxjh3f.pdf'),
]
for destination, attachment in attachments:
    subprocess.run(['curl', '--fail', '--silent', '--show-error', '--max-time', '90', '-o', str(destination), 'https://r2-pub.rork.com/attachments/' + attachment], check=True)
    print(f'Saved {destination}: {destination.stat().st_size} bytes')
frames = media / 'frames'
frames.mkdir(exist_ok=True)
subprocess.run(['ffmpeg', '-hide_banner', '-loglevel', 'error', '-y', '-i', str(media / 'reference.mp4'), '-vf', 'fps=1/6,scale=640:-2', str(frames / '%03d.jpg')], check=True)
print('Frames: ' + str(frames))
sys.path.insert(0, str(Path(os.environ['TMPDIR']) / 'knot-pdf-tools'))
try:
    from pypdf import PdfReader
    (review / 'document-creation-pdf.txt').write_text('\n'.join(page.extract_text() for page in PdfReader(media / 'document-creation.pdf').pages))
    print('PDF extracted')
except ImportError:
    print('PDF extraction requires pypdf; Markdown reference saved.')
