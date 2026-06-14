#!/usr/bin/env bash
# Build an arXiv-ready LaTeX SOURCE bundle from a paper's Markdown source.
#
# arXiv rejects PDFs created from TeX/LaTeX; it wants the source. This produces a
# directory (and a .zip) with main.tex + vector figures + a README, then compiles
# it locally as the gate. Deterministic code owns arXiv compatibility; an LLM is
# used only in the compile-fix loop (optional).
#
# Setup:   brew install pandoc tectonic librsvg
# Usage:   bin/build-arxiv.sh <source.md> [out-dir]
#          out-dir defaults to build/<slug>-arxiv/
#
# Optional LLM compile-fix loop (off unless set):
#   export MD2ARXIV_LLM='claude -p'    # any CLI that reads a prompt on stdin,
#                                      # prints the corrected main.tex on stdout
#
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="${1:?usage: build-arxiv.sh <source.md> [out-dir]}"
[ -f "$SRC" ] || { echo "source not found: $SRC" >&2; exit 1; }

base="$(basename "$SRC" .md)"
slug="${base#[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]-}"   # strip leading date
BUNDLE="${2:-build/$slug-arxiv}"
ASSETS="${MD2ARXIV_ASSETS:-public/assets}"                   # where /assets/*.svg live

rm -rf "$BUNDLE"; mkdir -p "$BUNDLE"

# --- frontmatter -> pandoc metadata ---
FM="$(awk 'NR==1 && $0=="---"{f=1;next} f && $0=="---"{exit} f{print}' "$SRC")"
fmval(){ printf '%s\n' "$FM" | sed -n "s/^$1: *//p" | head -1 | sed -e 's/^"//' -e 's/"$//'; }
TITLE="$(fmval title)"; TITLE="${TITLE:-$slug}"
SUBTITLE="$(fmval subtitle)"
DATE="$(printf '%s' "$base" | grep -oE '^[0-9]{4}-[0-9]{2}-[0-9]{2}' || true)"

echo "==> arXiv bundle for '$TITLE'"
echo "    source: $SRC"
echo "    bundle: $BUNDLE"

# --- figures: svg -> vector PDF, keep the basename (already arXiv-safe) ---
echo "==> Converting referenced SVG figures to vector PDF"
grep -oE '/assets/[a-z0-9-]+\.svg' "$SRC" | sort -u | while read -r ref; do
  svg="$ASSETS/$(basename "$ref")"; bn="$(basename "$ref" .svg)"
  [ -f "$svg" ] || { echo "    missing $svg, skipping" >&2; continue; }
  rsvg-convert -f pdf "$svg" -o "$BUNDLE/$bn.pdf"
  echo "    $ref -> $bn.pdf"
done

# --- preprocess markdown: strip frontmatter, point figures at the bundle PDFs,
#     fold glyphs the default LaTeX font lacks. Tables/figures stay raw HTML and
#     are converted to native LaTeX by the Lua filter. ---
echo "==> Preprocessing markdown"
PRE="$BUNDLE/.paper.md"
SITE="${MD2ARXIV_SITE:-https://june.kim}"
# - point figure <img> at the bundle PDFs and turn <figure>/<img> into markdown
#   images (the markdown reader splits multi-line raw <figure> blocks, dropping the
#   <img>, so we convert deterministically rather than via the Lua filter);
# - rewrite site-relative links to absolute URLs for a standalone PDF;
# - tables stay raw HTML and become native LaTeX via the Lua filter;
# - fold glyphs the default LaTeX font lacks.
sed '1{/^---$/!q;};1,/^---$/d' "$SRC" \
  | sed -E 's#/assets/([a-z0-9-]+)\.svg#\1.pdf#g' \
  | sed -E 's#<img[^>]*src="([^"]+)"[^>]*>#\n![](\1)\n#g' \
  | sed -E 's#</?figure[^>]*>##g; s#</?figcaption[^>]*>##g' \
  | sed -E "s#\]\(/#](${SITE}/#g" \
  | sed -E "s#href=\"/#href=\"${SITE}/#g" \
  | sed -E 's/`(S_n|p_0|p_1|p₀|p₁|ε|X_i|FAIL_TO_PASS|PASS_TO_PASS|H|T|N|K)`/$\1$/g' \
  | sed 's/✓/Y/g; s/✗/N/g; s/◐/~/g; s/·/, /g; s/→/->/g; s/⇒/=>/g; s/≥/>=/g; s/≤/<=/g' \
  > "$PRE"

# --- pandoc: markdown -> LaTeX source (not PDF) ---
echo "==> pandoc: markdown -> main.tex"
HEADER="$BUNDLE/.header.tex"
{ echo '\pdfoutput=1'; } > "$HEADER"     # tell arXiv to use pdfLaTeX
SUB_ARG=(); [ -n "$SUBTITLE" ] && SUB_ARG=(-V subtitle="$SUBTITLE")
DATE_ARG=(); [ -n "$DATE" ] && DATE_ARG=(-V date="$DATE")

( cd "$BUNDLE" && pandoc ".paper.md" \
    --standalone \
    --from markdown+raw_html+pipe_tables+yaml_metadata_block \
    --to latex \
    --lua-filter "$HERE/filters/html-tables.lua" \
    --include-in-header ".header.tex" \
    -V documentclass=article \
    -V geometry:margin=1in \
    -V fontsize=10pt \
    -V linkcolor=blue -V urlcolor=blue \
    -V title="$TITLE" "${SUB_ARG[@]}" -V author="June Kim" "${DATE_ARG[@]}" \
    --toc --toc-depth=2 --number-sections \
    -o main.tex )

# --- README + cleanup of scratch ---
cat > "$BUNDLE/00README.txt" <<EOF
arXiv LaTeX source bundle for: $TITLE
Compile: pdflatex main.tex   (or: tectonic main.tex)
Generated from Markdown by md2arxiv (bin/build-arxiv.sh). Figures are vector PDF.
EOF
rm -f "$PRE" "$HEADER"

# --- arXiv-convention checks (hard fail) ---
echo "==> arXiv checks"
fail=0
if find "$BUNDLE" -iname '*.svg' | grep -q .; then echo "  FAIL: .svg in bundle" >&2; fail=1; fi
if grep -qE '\\includegraphics(\[[^]]*\])?\{[^}]*(/|assets)' "$BUNDLE/main.tex"; then echo "  FAIL: figure include is not a bare bundle filename" >&2; fail=1; fi
if ! grep -q '\\pdfoutput=1' "$BUNDLE/main.tex"; then echo "  FAIL: missing \\pdfoutput=1" >&2; fail=1; fi
if find "$BUNDLE" -name '*[ :&()]*' | grep -q .; then echo "  FAIL: fragile filename" >&2; fail=1; fi
[ "$fail" = 0 ] || { echo "==> arXiv checks failed; bundle left at $BUNDLE for inspection" >&2; exit 1; }
echo "    checks pass"

# --- compile gate (kill condition), with optional bounded LLM fix loop ---
compile(){ ( cd "$BUNDLE" && tectonic -k main.tex ) >"$BUNDLE/.compile.log" 2>&1; }
echo "==> Compile gate (tectonic)"
if compile; then
  echo "    compiled: $BUNDLE/main.pdf"
else
  echo "    first compile failed"
  if [ -n "${MD2ARXIV_LLM:-}" ]; then
    for i in 1 2 3; do
      echo "==> LLM compile-fix attempt $i ($MD2ARXIV_LLM)"
      { echo "Patch this arXiv pdfLaTeX document so it compiles. Return the COMPLETE corrected main.tex and nothing else (no prose, no code fences)."
        echo; echo "===== tectonic error log (tail) ====="; tail -40 "$BUNDLE/.compile.log"
        echo; echo "===== main.tex ====="; cat "$BUNDLE/main.tex"
      } | $MD2ARXIV_LLM > "$BUNDLE/.main.fixed" || { echo "    LLM call failed" >&2; break; }
      # strip accidental ``` fences if the model added them
      sed -E '/^```/d' "$BUNDLE/.main.fixed" > "$BUNDLE/main.tex"; rm -f "$BUNDLE/.main.fixed"
      if compile; then echo "    fixed on attempt $i: $BUNDLE/main.pdf"; break; fi
      [ "$i" = 3 ] && { echo "==> still failing after 3 attempts; see $BUNDLE/.compile.log" >&2; exit 1; }
    done
  else
    echo "    set MD2ARXIV_LLM to enable the compile-fix loop; see $BUNDLE/.compile.log" >&2
    exit 1
  fi
fi

# --- optional cleaner + zip the SOURCE (not the compiled pdf/aux) ---
command -v arxiv_latex_cleaner >/dev/null 2>&1 && arxiv_latex_cleaner "$BUNDLE" --keep_bib >/dev/null 2>&1 || true
ZIP="$BUNDLE.zip"; rm -f "$ZIP"
# Include the source: main.tex + figure PDFs + README. Drop the compiled main.pdf
# and TeX aux/log so the zip is source-only (figure PDFs are kept).
( cd "$BUNDLE" && zip -q -r "../$(basename "$BUNDLE").zip" . \
    -x 'main.pdf' -x '.*' -x '*.aux' -x '*.log' -x '*.out' -x '*.toc' )
echo "==> Wrote $BUNDLE/ and $ZIP"
echo "    upload $ZIP to arXiv (main.tex + figures). Inspect $BUNDLE/main.pdf first."
