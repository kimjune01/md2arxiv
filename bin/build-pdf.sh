#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Reading/download PDF for a paper. It IS the arXiv composition's compiled PDF,
# so the downloadable PDF and the arXiv submission share one look (kourgeorge
# arxiv-style). This is a thin wrapper around build-arxiv.sh; all the real work
# (figures, tables, abstract, style, compile gate) lives there.
#
# Setup:   brew install pandoc tectonic librsvg
# Usage:   bin/build-pdf.sh <source.md> [output.pdf]
#          Output defaults to public/assets/<slug>.pdf.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="${1:?usage: build-pdf.sh <source.md> [output.pdf]}"
[ -f "$SRC" ] || { echo "source not found: $SRC" >&2; exit 1; }

base="$(basename "$SRC" .md)"
slug="${base#[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]-}"
OUT="${2:-public/assets/$slug.pdf}"

tmp="$(mktemp -d -t md2arxiv-pdf.XXXXXX)"
trap 'rm -rf "$tmp"' EXIT

bash "$HERE/bin/build-arxiv.sh" "$SRC" "$tmp/bundle"
mkdir -p "$(dirname "$OUT")"
cp "$tmp/bundle/main.pdf" "$OUT"
echo "==> Wrote $OUT (arXiv-styled)"
ls -lh "$OUT"
