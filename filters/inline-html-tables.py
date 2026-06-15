#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# Replace each raw-HTML <table>...</table> block on stdin with its LaTeX
# rendering (pandoc's HTML reader, which grids these tables correctly), wrapped
# as a raw-latex block so the main markdown->latex pass passes it through.
#
# Why a preprocessing step and not a pandoc Lua filter: pandoc's *markdown*
# reader splits a block-level HTML table into one RawBlock per tag, so a filter
# never sees a whole <table>. pandoc's *html* reader handles the same table fine,
# so we convert each table out-of-band here.
import re, subprocess, sys

src = sys.stdin.read()

def convert(m):
    html = m.group(0)
    try:
        tex = subprocess.run(
            ["pandoc", "-f", "html", "-t", "latex"],
            input=html, capture_output=True, text=True, check=True,
        ).stdout.strip()
    except Exception:
        return html  # leave raw; the build's "no <table> left" check will flag it
    return "\n\n```{=latex}\n" + tex + "\n```\n\n"

sys.stdout.write(re.sub(r"<table\b.*?</table>", convert, src, flags=re.S | re.I))
