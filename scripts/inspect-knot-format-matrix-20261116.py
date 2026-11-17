"""Independent read-only format/content inspection of immutable synthetic files.
Office inspection validates archive structure/text/cells, not Office rendering.
PDF rendering uses two independent parsers; visual review remains separate.
"""
import sys, json, hashlib, csv, io, zipfile, re
from pathlib import Path
from xml.etree import ElementTree as ET
from html.parser import HTMLParser

source, output, kind = Path(sys.argv[1]), Path(sys.argv[2]), sys.argv[3]
output.mkdir(parents=True, exist_ok=False)
raw = source.read_bytes()
result = dict(format=kind, sha256=hashlib.sha256(raw).hexdigest(), bytes=len(raw), newExecutionOrReplay=False)
text, renders = '', []
expected_rows = [['Plant', 'Containers', 'WeeklyWaterChecks'], ['Basil', '2', '3'], ['Mint', '1', '4']]
if kind == 'pdf':
    import pymupdf
    from pypdf import PdfReader
    reader, doc = PdfReader(source), pymupdf.open(source)
    assert len(reader.pages) == len(doc) and 1 <= len(doc) <= 5, 'page_count'
    text = '\n'.join(p.extract_text() or '' for p in reader.pages)
    result['pages'] = len(doc)
    for i, page in enumerate(doc):
        path = output / f'page-{i + 1}.png'
        page.get_pixmap(matrix=pymupdf.Matrix(1.25, 1.25)).save(path)
        renders.append(str(path))
    result.update(renders=renders, visualInspection='pending')
elif kind in ('docx', 'xlsx', 'pptx'):
    with zipfile.ZipFile(io.BytesIO(raw)) as archive:
        names = archive.namelist()
        assert len(names) == len(set(names)) and len(names) <= 1000, 'archive_entries'
        assert sum(i.file_size for i in archive.infolist()) <= 50000000, 'archive_expansion'
        assert '[Content_Types].xml' in names and '_rels/.rels' in names, 'office_package'
        assert not any('vbaproject' in n.lower() for n in names), 'unexpected_macro'
        ns = {'w': 'http://schemas.openxmlformats.org/wordprocessingml/2006/main', 's': 'http://schemas.openxmlformats.org/spreadsheetml/2006/main', 'a': 'http://schemas.openxmlformats.org/drawingml/2006/main'}
        if kind == 'docx':
            root = ET.fromstring(archive.read('word/document.xml'))
            text = ' '.join(n.text or '' for n in root.findall('.//w:t', ns))
        elif kind == 'pptx':
            slides = sorted(n for n in names if re.fullmatch(r'ppt/slides/slide\d+\.xml', n))
            assert len(slides) == 4, 'slide_count'
            text = '\n'.join(' '.join(n.text or '' for n in ET.fromstring(archive.read(s)).findall('.//a:t', ns)) for s in slides)
            result['slides'] = len(slides)
        else:
            workbook = ET.fromstring(archive.read('xl/workbook.xml'))
            sheets = workbook.findall('s:sheets/s:sheet', ns)
            assert len(sheets) == 1 and sheets[0].get('name') == 'Balcony Herb Plan', 'sheet_identity'
            strings = []
            if 'xl/sharedStrings.xml' in names:
                strings = [''.join(n.itertext()) for n in ET.fromstring(archive.read('xl/sharedStrings.xml')).findall('s:si', ns)]
            root = ET.fromstring(archive.read('xl/worksheets/sheet1.xml'))
            cells = {}
            for cell in root.findall('.//s:sheetData/s:row/s:c', ns):
                assert cell.find('s:f', ns) is None, 'unexpected_formula'
                value = cell.find('s:v', ns)
                value = value.text if value is not None else ''.join(cell.find('s:is', ns).itertext()) if cell.find('s:is', ns) is not None else ''
                cells[cell.get('r')] = strings[int(value)] if cell.get('t') == 's' else value
            expected = {f'{col}{row}': expected_rows[row - 1][column] for row in range(1, 4) for column, col in enumerate('ABC')}
            assert cells == expected, 'spreadsheet_cells'
            result['cells'] = cells
            text = 'Balcony Herb Plan ' + ' '.join(cells.values())
    result['officeRendering'] = 'not_independently_exercised'
else:
    assert not raw.startswith((b'%PDF-', b'PK')), 'format_substitution'
    text = raw.decode('utf-8', errors='strict')
    assert '\x00' not in text and text.strip(), 'raw_utf8'
    if kind == 'csv':
        rows = list(csv.reader(io.StringIO(text)))
        assert rows == expected_rows, 'csv_exact_rows'
        result['rows'] = rows
    elif kind == 'json':
        value = json.loads(text)
        assert value == dict(title='Balcony Herb Plan', plants=[dict(name='Basil', containers=2, weeklyWaterChecks=3), dict(name='Mint', containers=1, weeklyWaterChecks=4)]), 'json_exact_values'
        result['value'] = value
    elif kind == 'html':
        class Visible(HTMLParser):
            def __init__(self):
                super().__init__(); self.skip = 0; self.parts = []
            def handle_starttag(self, tag, attrs):
                assert tag not in ('script', 'iframe', 'object', 'embed', 'link'), 'active_or_remote_html'
                assert all(k not in ('src',) and not k.startswith('on') for k, _ in attrs), 'external_or_active_attribute'
                if tag in ('style', 'head'): self.skip += 1
            def handle_endtag(self, tag):
                if tag in ('style', 'head'): self.skip -= 1
            def handle_data(self, data):
                if not self.skip: self.parts.append(data)
        parser = Visible(); parser.feed(text); parser.close(); text = ' '.join(parser.parts)
if kind != 'csv':
    assert 'balcony herb plan' in ' '.join(text.lower().split()), 'title_missing'
assert 'Basil' in text and 'Mint' in text, 'requested_plant_missing'
if kind not in ('csv', 'json', 'xlsx'):
    assert all(word in text.lower() for word in ['water', 'harvest']), 'practical_content_missing'
result['text'] = text
(output / 'inspection.json').write_text(json.dumps(result, indent=2))
print(json.dumps(result))
