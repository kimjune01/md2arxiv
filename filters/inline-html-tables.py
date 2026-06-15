#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# Replace each raw-HTML <table>...</table> block on stdin with an equivalent
# pandoc grid-table (Markdown), so the main markdown->LaTeX pass renders it as a
# real, page-fitting table (pandoc computes wrapping column widths and loads the
# table packages itself).
#
# Why a preprocessing step and not a pandoc Lua filter: pandoc's *markdown*
# reader splits a block-level HTML table into one RawBlock per tag, so a filter
# never sees a whole <table>. pandoc's *html* reader handles it fine, so we
# convert each table out-of-band here. Grid tables (not latex) are emitted so the
# main run owns column sizing and preamble.
import re, subprocess, sys

src = sys.stdin.read()

# Force grid tables (robust round-trip + relative widths -> wrapping columns).
TO = "markdown-simple_tables-multiline_tables-pipe_tables"

def convert(m):
    html = m.group(0)
    try:
        md = subprocess.run(
            ["pandoc", "-f", "html", "-t", TO],
            input=html, capture_output=True, text=True, check=True,
        ).stdout.strip()
    except Exception:
        return html  # leave raw; the build's "no <table> left" check will flag it
    return "\n\n" + md + "\n\n"

sys.stdout.write(re.sub(r"<table\b.*?</table>", convert, src, flags=re.S | re.I))
