"""Writes a text PDF with one titled passage per page and an internal link from page 1 to page 3."""
import sys


def build(pages, title):
    objects = {1: b'<< /Type /Catalog /Pages 2 0 R >>', 3: b'<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>'}
    page_ids = [4 + index * 3 for index in range(pages)]
    objects[2] = f'<< /Type /Pages /Kids [{" ".join(f"{p} 0 R" for p in page_ids)}] /Count {pages} >>'.encode()
    for index, page_id in enumerate(page_ids):
        lines = [f'BT /F1 26 Tf 60 700 Td ({title} - Page {index + 1}) Tj ET',
                 f'BT /F1 14 Tf 60 660 Td (Passage {index + 1} of {pages}. Synthetic reader acceptance text.) Tj ET']
        annotations = ''
        if index == 0 and pages >= 3:
            lines.append('BT /F1 14 Tf 60 600 Td (Jump to page 3) Tj ET')
            annotations = f' /Annots [{page_id + 2} 0 R]'
            objects[page_id + 2] = f'<< /Type /Annot /Subtype /Link /Rect [55 590 220 620] /Border [0 0 0] /Dest [{page_ids[2]} 0 R /Fit] >>'.encode()
        content = '\n'.join(lines).encode()
        objects[page_id] = f'<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Resources << /Font << /F1 3 0 R >> >> /Contents {page_id + 1} 0 R{annotations} >>'.encode()
        objects[page_id + 1] = f'<< /Length {len(content)} >>\nstream\n'.encode() + content + b'\nendstream'
    size = max(objects) + 1
    data = b'%PDF-1.4\n'
    offsets = {}
    for number in sorted(objects):
        offsets[number] = len(data)
        data += f'{number} 0 obj\n'.encode() + objects[number] + b'\nendobj\n'
    xref = len(data)
    data += f'xref\n0 {size}\n0000000000 65535 f \n'.encode()
    for number in range(1, size):
        data += f'{offsets[number]:010} 00000 n \n'.encode() if number in offsets else b'0000000000 65535 f \n'
    data += f'trailer\n<< /Size {size} /Root 1 0 R /Info << /Title ({title}) >> >>\nstartxref\n{xref}\n%%EOF\n'.encode()
    return data


if __name__ == '__main__':
    path, pages, title = sys.argv[1], int(sys.argv[2]), sys.argv[3]
    with open(path, 'wb') as output:
        output.write(build(pages, title))
