#!/usr/bin/env python3
"""A manual in Markdown -> an A4 PDF, screenshots included.

  mkmanual.py manual.md manual.pdf

Needs the `markdown` and `fpdf2` Python packages (pip install markdown fpdf2) and the
DejaVu fonts (for Greek and the arrow keys). Images are referenced relative to the
Markdown file.
"""
import os
import re
import sys

import markdown
from fpdf import FPDF

FONT_DIR = '/usr/share/fonts/truetype/dejavu'
FONTS = {'': 'DejaVuSans.ttf', 'B': 'DejaVuSans-Bold.ttf', 'I': 'DejaVuSans-Oblique.ttf',
         'BI': 'DejaVuSans-BoldOblique.ttf'}
MONO = 'DejaVuSansMono.ttf'
IMAGE_W = 120               # mm: the overscan screen, 768x544 shots
ACCENT = '#b00000'          # the theatre's curtain red, darker for paper


class Manual(FPDF):
    def __init__(self, title):
        super().__init__(format='A4')
        self.title_text = title
        for style, name in FONTS.items():
            self.add_font('DejaVu', style, os.path.join(FONT_DIR, name))
        self.add_font('DejaVuMono', '', os.path.join(FONT_DIR, MONO))
        self.set_margins(20, 18, 20)
        self.set_auto_page_break(True, 18)

    def footer(self):
        self.set_y(-12)
        self.set_font('DejaVu', '', 8)
        self.set_text_color(120)
        self.cell(0, 6, f'{self.title_text}  ·  {self.page_no()}', align='C')


def to_html(md_text, base):
    html = markdown.markdown(md_text, extensions=['tables'])
    # images: absolute paths, a fixed width, centred on their own line
    def img(m):
        src = os.path.join(base, m.group(1))
        return f'<p align="center"><img src="{src}" width="{IMAGE_W * 72 / 25.4:.0f}"></p>'  # pt
    html = re.sub(r'<p><img alt="[^"]*" src="([^"]+)" ?/?></p>', img, html)
    # headings in the accent colour
    html = re.sub(r'<(h[123])>', lambda m: f'<{m.group(1)}><font color="{ACCENT}">', html)
    html = re.sub(r'</(h[123])>', lambda m: f'</font></{m.group(1)}>', html)
    # tables: full width; fpdf2 takes no markup inside a cell, so bold/code there goes
    html = re.sub(r'<(td|th)(\s[^>]*)?>(.*?)</\1>',
                  lambda m: f'<{m.group(1)}{m.group(2) or ""}>{re.sub(r"<[^>]+>", "", m.group(3))}</{m.group(1)}>',
                  html, flags=re.S)
    html = re.sub(r'<table>(.*?)</table>', table_widths, html, flags=re.S)
    return html


def table_widths(m):
    """Columns as wide as their longest text (at least 15%), set on the heading cells."""
    body = m.group(1)
    rows = re.findall(r'<tr>(.*?)</tr>', body, re.S)
    cells = [re.findall(r'<t[hd](?:\s[^>]*)?>(.*?)</t[hd]>', r, re.S) for r in rows]
    n = max(len(c) for c in cells)
    longest = [max((len(c[i]) for c in cells if i < len(c)), default=1) or 1 for i in range(n)]
    total = sum(longest)
    pct = [max(15, round(100 * l / total)) for l in longest]
    pct[-1] = 100 - sum(pct[:-1])
    head = iter(pct)
    body = re.sub(r'<th(?=[\s>])', lambda _: f'<th width="{next(head)}%"', body, count=n)
    return f'<table width="100%" border="1">{body}</table>'


def main(argv):
    if len(argv) != 3:
        sys.exit(__doc__)
    src, dst = argv[1], argv[2]
    text = open(src, encoding='utf-8').read()
    title = re.search(r'^# (.+)$', text, re.M).group(1)
    pdf = Manual(title)
    pdf.add_page()
    pdf.set_font('DejaVu', '', 10.5)
    html = to_html(text, os.path.dirname(os.path.abspath(src)))
    # a section at a time, so a heading is never left at the foot of a page: it needs
    # room for a picture after it if one follows, else for a few lines
    for chunk in re.split(r'(?=<h[123]>)', html):
        if not chunk.strip():
            continue
        if chunk.startswith('<h'):
            picture = re.match(r'<h[123]>.*?</h[123]>\s*<p align="center"><img', chunk, re.S)
            need = IMAGE_W * 544 / 768 + 25 if picture else 35
            if pdf.get_y() > pdf.h - pdf.b_margin - need:
                pdf.add_page()
        pdf.write_html(chunk, font_family='DejaVu', pre_code_font='DejaVuMono')
    pdf.output(dst)
    print(f"{dst}: {pdf.page_no()} pages")


if __name__ == '__main__':
    main(sys.argv)
