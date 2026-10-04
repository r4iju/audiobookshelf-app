import pathlib
import re
import sys

root = pathlib.Path(sys.argv[1])
output = pathlib.Path(sys.argv[2])
parts = []
for directory in [root / 'libarchive-3.7.2/libarchive', root / 'xz-5.2.11/src/liblzma', root / 'xz-5.2.11/src/common']:
    for source in sorted(directory.rglob('*')):
        if source.suffix not in ['.c', '.h'] or 'test' in source.parts:
            continue
        text = source.read_text(errors='replace')
        # The upstream file header carries the controlling grant and attribution.
        header = re.match(r'\s*((?:/\*.*?\*/\s*|//[^\n]*\n\s*)+)', text, re.S)
        if header and re.search(r'copyright|license|public domain|permission', header[1], re.I):
            parts.append(str(source.relative_to(root)) + '\n' + header[1].strip())
output.write_text('Comic decoder source-file notices\n\n' + '\n\n'.join(parts) + '\n')
