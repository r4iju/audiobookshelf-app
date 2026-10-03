"""Generate small authored books with identifiable passages and comic panels locally."""
import argparse
import struct
import subprocess
import tempfile
import zipfile
import zlib
from pathlib import Path
parser = argparse.ArgumentParser()
parser.add_argument('output', type=Path)
args = parser.parse_args()
args.output.mkdir(parents=True, exist_ok=True)
with tempfile.TemporaryDirectory() as directory:
    work = Path(directory)
    html = '<html><head><title>Reader Field Notes</title></head><body>'
    for chapter in range(1, 4):
        html += f'<h1>Field chapter {chapter}</h1>'
        for passage in range(1, 25):
            html += f'<p>Field passage {chapter}.{passage}. The observatory window looks across the quiet valley. Synthetic reading notes for navigation and restoration.</p>'
    html += '</body></html>'
    (work / 'stories.html').write_text(html)
    for fmt in ('mobi', 'azw3'):
        subprocess.run(['ebook-convert', str(work / 'stories.html'), str(args.output / ('stories.' + fmt)), '--chapter', '//h:h1', '--level1-toc', '//h:h1'], check=True, stdout=subprocess.DEVNULL)
    def chunk(kind, value):
        return struct.pack('>I', len(value)) + kind + value + struct.pack('>I', zlib.crc32(kind + value))
    for page, color in [(10, (30, 80, 220)), (2, (30, 180, 70)), (1, (220, 50, 30))]:
        image = b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', 600, 800, 8, 2, 0, 0, 0))
        image += chunk(b'IDAT', zlib.compress((b'\0' + bytes(color) * 600) * 800)) + chunk(b'IEND', b'')
        (work / f'Panel {page}.png').write_bytes(image)
    (work / 'ComicInfo.xml').write_text('<ComicInfo><Title>Three windows</Title><Writer>Fixture Studio</Writer></ComicInfo>')
    with zipfile.ZipFile(args.output / 'stories.cbz', 'w', zipfile.ZIP_DEFLATED) as archive:
        for file in work.glob('*.png'): archive.write(file, file.name)
        archive.write(work / 'ComicInfo.xml', 'ComicInfo.xml')
    subprocess.run(['rar', 'a', '-idq', str(args.output / 'stories.cbr'), 'Panel 10.png', 'Panel 2.png', 'Panel 1.png', 'ComicInfo.xml'], cwd=work, check=True)
