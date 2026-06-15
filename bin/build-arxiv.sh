#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Build an arXiv-ready LaTeX SOURCE bundle from a paper's Markdown source.
#
# arXiv rejects PDFs created from TeX/LaTeX; it wants the source. This produces a
# directory (and a .zip) with main.tex + vector figures + a README, then compiles
# it locally as the gate. Deterministic code owns arXiv compatibility; an LLM is
# used only in the optional compile-fix loop.
#
# Setup:   brew install pandoc tectonic librsvg
# Usage:   bin/build-arxiv.sh <source.md> [out-dir]
#          out-dir defaults to build/<slug>-arxiv/
#
# NOTE on the compile gate: arXiv compiles pdfLaTeX (TeX Live). The local gate
# here is tectonic (XeTeX-based), a convenient proxy, not identical. Glyphs are
# folded to ASCII to narrow the gap, but inspect main.pdf and arXiv's own compile
# output on first upload. Install TeX Live and swap in `pdflatex` for an exact gate.
#
# Optional LLM compile-fix loop (off unless set):
#   export MD2ARXIV_LLM='claude -p'    # CLI that reads a prompt on stdin and
#                                      # prints the corrected main.tex on stdout
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="${1:?usage: build-arxiv.sh <source.md> [out-dir]}"
[ -f "$SRC" ] || { echo "source not found: $SRC" >&2; exit 1; }

base="$(basename "$SRC" .md)"
slug="${base#[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]-}"
BUNDLE="${2:-build/$slug-arxiv}"
ASSETS="${MD2ARXIV_ASSETS:-public/assets}"
SITE="${MD2ARXIV_SITE:-https://june.kim}"

rm -rf "$BUNDLE"; mkdir -p "$BUNDLE"

FM="$(awk 'NR==1 && $0=="---"{f=1;next} f && $0=="---"{exit} f{print}' "$SRC")"
fmval(){ printf '%s\n' "$FM" | sed -n "s/^$1: *//p" | head -1 | sed -e 's/^"//' -e 's/"$//'; }
TITLE="$(fmval title)"; TITLE="${TITLE:-$slug}"
SUBTITLE="$(fmval subtitle)"
DATE="$(printf '%s' "$base" | grep -oE '^[0-9]{4}-[0-9]{2}-[0-9]{2}' || true)"

echo "==> arXiv bundle for '$TITLE'"
echo "    source: $SRC"
echo "    bundle: $BUNDLE"

# --- figures: svg -> vector PDF; a referenced-but-missing figure is a hard fail ---
echo "==> Converting referenced SVG figures to vector PDF"
missing=0
while read -r ref; do
  [ -n "$ref" ] || continue
  svg="$ASSETS/$(basename "$ref")"; bn="$(basename "$ref" .svg)"
  if [ -f "$svg" ]; then
    rsvg-convert -f pdf "$svg" -o "$BUNDLE/$bn.pdf"; echo "    $ref -> $bn.pdf"
  else
    echo "    MISSING referenced figure: $svg" >&2; missing=1
  fi
done < <(grep -oE '/assets/[a-z0-9-]+\.svg' "$SRC" | sort -u || true)
[ "$missing" = 0 ] || { echo "==> referenced figures missing; aborting" >&2; exit 1; }

# --- preprocess markdown (see README for the rules) ---
echo "==> Preprocessing markdown"
PRE="$BUNDLE/.paper.md"
sed '1{/^---$/!q;};1,/^---$/d' "$SRC" \
  | sed '/\[Download PDF\]/d' \
  | perl -0777 -pe 's{(<figure\b.*?</figure>)}{ index(lc($1),"<img")>=0 || index(lc($1),"<table")>=0 ? $1 : "" }gse' \
  | sed -E 's#/assets/([a-z0-9-]+)\.svg#\1.pdf#g' \
  | sed -E 's#<img[^>]*src="([^"]+)"[^>]*>#\n![](\1)\n#g' \
  | sed -E 's#</?figure[^>]*>##g; s#</?figcaption[^>]*>##g' \
  | sed -E "s#\]\(/#](${SITE}/#g" \
  | sed -E "s#href=\"/#href=\"${SITE}/#g" \
  | sed -E 's/`S_n`/$S_n$/g; s/`X_i`/$X_i$/g; s/`p_0`|`p₀`/$p_0$/g; s/`p_1`|`p₁`/$p_1$/g; s/`ε`/$\\epsilon$/g' \
  | sed 's/✓/Y/g; s/✗/N/g; s/◐/~/g; s/·/, /g; s/→/->/g; s/⇒/=>/g; s/≥/>=/g; s/≤/<=/g' \
  | python3 "$HERE/filters/inline-html-tables.py" \
  | perl -0pe 's#<style\b.*?</style>##gis; s#</?(span|div)\b[^>]*>##gi' \
  > "$PRE"

# --- pandoc: markdown -> LaTeX source (not PDF) ---
echo "==> pandoc: markdown -> main.tex"
SUB_ARG=(); [ -n "$SUBTITLE" ] && SUB_ARG=(-V subtitle="$SUBTITLE")
DATE_ARG=(); [ -n "$DATE" ] && DATE_ARG=(-V date="$DATE")
( cd "$BUNDLE" && pandoc ".paper.md" \
    --standalone \
    --from markdown+raw_html+pipe_tables+yaml_metadata_block \
    --to latex \
    --include-in-header "$HERE/filters/table-preamble.tex" \
    -V documentclass=article -V geometry:margin=1in -V fontsize=10pt \
    -V linkcolor=blue -V urlcolor=blue \
    -V title="$TITLE" "${SUB_ARG[@]}" -V author="June Kim" "${DATE_ARG[@]}" \
    --number-sections \
    -o main.tex )

cat > "$BUNDLE/00README.txt" <<EOF
arXiv LaTeX source bundle for: $TITLE
Compile: pdflatex main.tex   (local gate used: tectonic main.tex)
Generated from Markdown by md2arxiv (bin/build-arxiv.sh). Figures are vector PDF.
EOF
rm -f "$PRE"

# --- arXiv-convention checks (run on the FINAL main.tex, after any LLM rewrite) ---
arxiv_checks(){
  local fail=0 g
  find "$BUNDLE" -iname '*.svg' | grep -q . && { echo "  FAIL: .svg in bundle" >&2; fail=1; }
  head -5 "$BUNDLE/main.tex" | grep -q '\\pdfoutput=1' || { echo "  FAIL: \\pdfoutput=1 not in first 5 lines" >&2; fail=1; }
  grep -qE '\\includegraphics(\[[^]]*\])?\{[^}]*(/|assets)' "$BUNDLE/main.tex" && { echo "  FAIL: figure include is not a bare bundle filename" >&2; fail=1; }
  grep -q '<table' "$BUNDLE/main.tex" && { echo "  FAIL: raw HTML <table> left in main.tex (Lua filter did not convert it)" >&2; fail=1; }
  # every \includegraphics target must exist in the bundle
  while read -r g; do
    [ -n "$g" ] || continue
    [ -f "$BUNDLE/$g" ] || { echo "  FAIL: figure referenced but not in bundle: $g" >&2; fail=1; }
  done < <(grep -oE '\\includegraphics(\[[^]]*\])?\{[^}]*\}' "$BUNDLE/main.tex" | sed -E 's/.*\{([^}]*)\}/\1/' | sort -u || true)
  # fragile filenames in the bundle (basename level)
  find "$BUNDLE" -type f ! -name '.*' | sed 's#.*/##' | grep -qE '[ :&()%#$~]' && { echo "  FAIL: fragile filename in bundle" >&2; fail=1; }
  return $fail
}

# --- compile gate (kill condition), with optional bounded LLM fix loop ---
compile(){ ( cd "$BUNDLE" && tectonic -k main.tex ) >"$BUNDLE/.compile.log" 2>&1; }
echo "==> Compile gate (tectonic)"
if ! compile; then
  echo "    first compile failed"
  if [ -n "${MD2ARXIV_LLM:-}" ]; then
    ok=0
    for i in 1 2 3; do
      echo "==> LLM compile-fix attempt $i ($MD2ARXIV_LLM)"
      { echo "Patch this arXiv pdfLaTeX document so it compiles. Keep \\pdfoutput=1 in the first lines. Return the COMPLETE corrected main.tex and nothing else (no prose, no code fences)."
        echo; echo "===== tectonic error log (tail) ====="; tail -40 "$BUNDLE/.compile.log"
        echo; echo "===== main.tex ====="; cat "$BUNDLE/main.tex"
      } | $MD2ARXIV_LLM > "$BUNDLE/.main.fixed" || { echo "    LLM call failed" >&2; break; }
      sed -E '/^```/d' "$BUNDLE/.main.fixed" > "$BUNDLE/main.tex"; rm -f "$BUNDLE/.main.fixed"
      if compile; then echo "    fixed on attempt $i"; ok=1; break; fi
    done
    [ "$ok" = 1 ] || { echo "==> still failing; see $BUNDLE/.compile.log" >&2; exit 1; }
  else
    echo "    set MD2ARXIV_LLM to enable the compile-fix loop; see $BUNDLE/.compile.log" >&2
    exit 1
  fi
fi
echo "    compiled: $BUNDLE/main.pdf"

# arXiv needs \pdfoutput=1 in the first lines to pick pdfLaTeX, but that directive
# misleads tectonic's (XeTeX) hyperref driver, so add it only now, after the local
# gate has passed. arXiv compiles with pdfLaTeX where it is correct.
printf '\\pdfoutput=1\n%s' "$(cat "$BUNDLE/main.tex")" > "$BUNDLE/main.tex"

echo "==> arXiv checks (final)"
arxiv_checks || { echo "==> arXiv checks failed; bundle left at $BUNDLE for inspection" >&2; exit 1; }
echo "    checks pass"

# --- zip the SOURCE (main.tex + figure PDFs + README), not compiled pdf/aux ---
ZIP="$BUNDLE.zip"; rm -f "$ZIP"
( cd "$BUNDLE" && zip -q -r "../$(basename "$BUNDLE").zip" . \
    -x 'main.pdf' -x '.*' -x '*.aux' -x '*.log' -x '*.out' -x '*.toc' )
echo "==> Wrote $BUNDLE/ and $ZIP"
echo "    upload $ZIP to arXiv. Inspect $BUNDLE/main.pdf first."
