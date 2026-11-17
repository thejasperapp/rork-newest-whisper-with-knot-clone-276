"""Extract a locally downloaded reference PDF without storing its contents in code."""
import argparse
from pathlib import Path
from pypdf import PdfReader

parser = argparse.ArgumentParser()
parser.add_argument("source", type=Path)
parser.add_argument("destination", type=Path)
args = parser.parse_args()
reader = PdfReader(args.source)
args.destination.write_text("\n\n".join(page.extract_text() or "" for page in reader.pages), encoding="utf-8")
print(f"Extracted {len(reader.pages)} pages.")
