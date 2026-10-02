"""Writes a small, valid synthetic EPUB 3 for the simulator export journey."""
import sys
import zipfile

chapters = 6
paragraph = "Synthetic text for the legacy export journey. " * 40

def chapter(number):
    body = "".join(f"<p>{paragraph}</p>" for _ in range(8))
    return f"""<?xml version="1.0" encoding="UTF-8"?>
<html xmlns="http://www.w3.org/1999/xhtml"><head><title>Chapter {number}</title></head>
<body><h1>Chapter {number}</h1>{body}</body></html>"""

manifest = "".join(f'<item id="c{n}" href="c{n}.xhtml" media-type="application/xhtml+xml"/>' for n in range(1, chapters + 1))
spine = "".join(f'<itemref idref="c{n}"/>' for n in range(1, chapters + 1))
nav_items = "".join(f'<li><a href="c{n}.xhtml">Chapter {n}</a></li>' for n in range(1, chapters + 1))

with zipfile.ZipFile(sys.argv[1], "w") as epub:
    epub.writestr("mimetype", "application/epub+zip", compress_type=zipfile.ZIP_STORED)
    epub.writestr("META-INF/container.xml", """<?xml version="1.0"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
<rootfiles><rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/></rootfiles>
</container>""", compress_type=zipfile.ZIP_DEFLATED)
    epub.writestr("OEBPS/content.opf", f"""<?xml version="1.0" encoding="UTF-8"?>
<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="id">
<metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
<dc:identifier id="id">urn:uuid:00000000-0000-4000-8000-00000000abcd</dc:identifier>
<dc:title>Synthetic Book</dc:title><dc:language>en</dc:language>
<meta property="dcterms:modified">2026-01-01T00:00:00Z</meta>
</metadata>
<manifest><item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>{manifest}</manifest>
<spine>{spine}</spine>
</package>""", compress_type=zipfile.ZIP_DEFLATED)
    epub.writestr("OEBPS/nav.xhtml", f"""<?xml version="1.0" encoding="UTF-8"?>
<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops"><head><title>Contents</title></head>
<body><nav epub:type="toc"><ol>{nav_items}</ol></nav></body></html>""", compress_type=zipfile.ZIP_DEFLATED)
    for n in range(1, chapters + 1):
        epub.writestr(f"OEBPS/c{n}.xhtml", chapter(n), compress_type=zipfile.ZIP_DEFLATED)
