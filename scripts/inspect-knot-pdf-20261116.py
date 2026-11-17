"""Read-only independent inspection of already downloaded immutable PDF bytes."""
import sys, json, hashlib
from pathlib import Path
import pymupdf
from pypdf import PdfReader

source, output = Path(sys.argv[1]), Path(sys.argv[2])
output.mkdir(parents=True, exist_ok=True)
raw = source.read_bytes()
reader = PdfReader(source)
page_texts = [page.extract_text() or '' for page in reader.pages]
text = '\n'.join(page_texts)
doc = pymupdf.open(source)
assert len(reader.pages) == len(doc) == 2, 'independent_page_count'
assert 'rainy day reading plan' in ' '.join(text.lower().split()), 'title_missing'
assert all(day in text for day in ['Friday', 'Saturday', 'Sunday']), 'schedule_missing'
images = []
for i, page in enumerate(doc):
    image = output / f'page-{i + 1}.png'
    page.get_pixmap(matrix=pymupdf.Matrix(1.5, 1.5)).save(image)
    images.append(str(image))
schedule_on_page_two = all(day in page_texts[1] and day not in page_texts[0] for day in ['Friday', 'Saturday', 'Sunday'])
result = {'scheduleEntirelyOnPageTwo': schedule_on_page_two, 'pageTexts': page_texts, 'original': str(source), 'sha256': hashlib.sha256(raw).hexdigest(), 'bytes': len(raw), 'pages': len(doc), 'text': text, 'renders': images, 'visualInspection': 'pending', 'newExecutionOrReplay': False}
print(json.dumps(result, indent=2))
(output / 'inspection.json').write_text(json.dumps(result, indent=2))
if '--require-page-assignment' in sys.argv:
    assert schedule_on_page_two, 'schedule_not_exclusively_page_two'
