"""Save the user-supplied references outside source control and extract PDFs.
Requires curl and pypdf installed under TMPDIR/knot-pdf-tools. Source files stay under TMPDIR; only local,
ignored extracts are created. Do not log credential-bearing document text.
"""
import os
import pathlib
import subprocess
import sys

sys.path.insert(0, str(pathlib.Path(os.environ['TMPDIR']) / 'knot-pdf-tools'))
from pypdf import PdfReader

root = pathlib.Path(__file__).resolve().parents[1]
source = pathlib.Path(os.environ['TMPDIR']) / 'knot-reference-review'
extracts = root / '.local/knot-references'
source.mkdir(parents=True, exist_ok=True)
extracts.mkdir(parents=True, exist_ok=True)
files = [
    ('system-v22', 'pdf', '1puryzabucn03jxl6lc3n.pdf'),
    ('shell-structure', 'pdf', 'jytqe24vihp3mt7oh7tqk.pdf'),
    ('master-spec', 'md', '4d0i5d4i8wc782o476b8w.md'),
    ('terminal-shell', 'md', '9n7rshqf8twu5yac8ewl4.md'),
    ('skill-set', 'md', 'hrdbcbazalbfzqvymcj2h.md'),
    ('skills-expansion', 'md', '09d6qs9lnm1w9n38bfpct.md'),
    ('skill-picks', 'md', '1m4jcgf4rqfn0v4flv8mc.md'),
    ('tool-loop', 'pdf', 'ct9pozuasbs2ub2ngk2kg.pdf'),
    ('muse-skills-mcp', 'md', 'woplclqq6p17sc01ysqax.md'),
]
for name, extension, attachment in files:
    path = source / (name + '.' + extension)
    subprocess.run(['curl', '--fail', '--silent', '--show-error', '--max-time', '45', '-o', str(path), 'https://r2-pub.rork.com/attachments/' + attachment], check=True)
    output = extracts / (name + '.txt')
    if extension == 'pdf':
        output.write_text('\n'.join(page.extract_text() for page in PdfReader(path).pages))
    else:
        output.write_bytes(path.read_bytes())
    print(name + ': extracted ' + str(output.stat().st_size) + ' bytes')
