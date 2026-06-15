#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# Convert raw-HTML <figure> and <table> blocks to clean Markdown so the main
# markdown->LaTeX pass renders real, captioned, numbered figures and tables.
# (pandoc's *markdown* reader otherwise shreds these blocks tag-by-tag.)
#
#   <figure> with <img>   -> ![caption](src)          (numbered figure + caption)
#   <figure> with <table> -> grid table + caption
#   <figure> with neither -> dropped (pure-HTML diagram)
#   bare <table>          -> grid table
#
# The figure <img src> must already point at the bundle PDF. A redundant leading
# "Figure."/"Table." label in the caption is stripped (LaTeX adds "Figure N:").
import re, subprocess, sys

TABLE_TO = "markdown-simple_tables-multiline_tables-pipe_tables"  # force grid tables

def pandoc(html, to):
    return subprocess.run(["pandoc", "-f", "html", "-t", to],
                          input=html, capture_output=True, text=True, check=True).stdout.strip()

def caption_of(block):
    m = re.search(r"<figcaption\b[^>]*>(.*?)</figcaption>", block, re.S | re.I)
    if not m:
        return ""
    try:
        c = pandoc(m.group(1), "markdown").strip()
    except Exception:
        c = re.sub(r"<[^>]+>", "", m.group(1)).strip()
    c = re.sub(r"\s+", " ", c)
    c = re.sub(r"^\*{0,2}(Figure|Table)\.\*{0,2}\s*", "", c)  # drop redundant label
    return c

def figure(m):
    fig = m.group(0)
    img = re.search(r'<img\b[^>]*src="([^"]+)"', fig, re.I)
    cap = caption_of(fig)
    if img:
        return "\n\n![%s](%s)\n\n" % (cap, img.group(1))
    tbl = re.search(r"<table\b.*?</table>", fig, re.S | re.I)
    if tbl:
        try:
            md = pandoc(tbl.group(0), TABLE_TO)
        except Exception:
            return fig
        return "\n\n" + md + ("\n\n  : " + cap if cap else "") + "\n\n"
    return ""  # pure-HTML diagram: drop

def table(m):
    try:
        return "\n\n" + pandoc(m.group(0), TABLE_TO) + "\n\n"
    except Exception:
        return m.group(0)

src = sys.stdin.read()
src = re.sub(r"<figure\b.*?</figure>", figure, src, flags=re.S | re.I)
src = re.sub(r"<table\b.*?</table>", table, src, flags=re.S | re.I)
sys.stdout.write(src)
