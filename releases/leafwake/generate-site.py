#!/usr/bin/env python3
"""Render the public privacy page from the policy bundled in the Android candidate."""
import html
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parent
parts = []
for block in (ROOT / 'PRIVACY.md').read_text().strip().split('\n\n'):
    text = html.escape(block.strip())
    text = re.sub(r'https://github.com/r4iju/audiobookshelf-app/issues',
                  '<a href="https://github.com/r4iju/audiobookshelf-app/issues">GitHub support issues</a>', text)
    if text.startswith('## '):
        parts.append('<h2>' + text[3:] + '</h2>')
    elif text.startswith('# '):
        parts.append('<h1>' + text[2:] + '</h1>')
    else:
        parts.append('<p>' + text + '</p>')
page = '''<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Leafwake privacy policy</title><link rel="stylesheet" href="style.css"></head><body><main class="policy"><nav aria-label="Main navigation"><a href="index.html">Leafwake</a><a href="privacy.html" aria-current="page">Privacy</a><a href="https://github.com/r4iju/audiobookshelf-app/issues">Support</a></nav>''' + '\n'.join(parts) + '</main></body></html>\n'
(ROOT / 'site/privacy.html').write_text(page)
print('Rendered public privacy policy from PRIVACY.md.')
