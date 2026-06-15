# md2arxiv

Turn an Astro/Markdown paper into (a) a reading PDF and (b) an arXiv-ready LaTeX
**source** bundle. The translation is deliberately thin: deterministic code owns
arXiv compatibility, an LLM is used only where the input is messy, and the
compiler is the gate. When a judgment call comes up, conform to arXiv conventions.

## Why source, not PDF

arXiv rejects PDFs that were produced from TeX/LaTeX and asks for the source
instead ([arXiv: submit/tex](https://info.arxiv.org/help/submit_tex.html)). A
`pandoc + tectonic` PDF is exactly such a PDF, so for arXiv you submit the
generated `.tex` + figures, not the PDF.

## Setup

```sh
brew install pandoc tectonic librsvg
# optional, for the cleaner step:
pipx install arxiv-latex-cleaner
```

## Use

```sh
# reading PDF (figures embedded), for a blog/download link:
bin/build-pdf.sh   path/to/2026-05-28-the-paper.md            # -> public/assets/the-paper.pdf

# arXiv LaTeX source bundle + zip, with a local compile gate:
bin/build-arxiv.sh path/to/2026-05-28-the-paper.md [out-dir]  # -> build/the-paper-arxiv/ + .zip
```

Both derive the title/subtitle from the YAML frontmatter, the date from the
filename, and the output name from the slug, so they are paper-agnostic. Point
them at any paper in the pipeline. `MD2ARXIV_ASSETS` overrides where `/assets/*.svg`
figures live (default `public/assets`); `MD2ARXIV_SITE` sets the base URL that
site-relative links rewrite to (default `https://june.kim`).

## What's deterministic vs LLM

**Deterministic (owns arXiv-compat):** strip frontmatter; rasterize referenced
SVGs to vector PDF; convert `<figure>/<img>` to markdown images; rewrite
site-relative links to absolute URLs; a preprocessing step
(`filters/inline-html-tables.py`) renders each raw-HTML table to LaTeX via
pandoc's HTML reader and inlines it (styling dropped, which is what arXiv wants),
because the markdown reader otherwise shreds tables tag-by-tag; pandoc emits
`main.tex`; arXiv-convention
checks (no `.svg`, bare figure filenames, `\pdfoutput=1`, safe names); assemble
the source-only zip; compile with tectonic as the gate.

**LLM (optional, off by default):** a bounded compile-fix loop. If the bundle
fails to compile and `MD2ARXIV_LLM` is set, the harness feeds the error log plus
`main.tex` to the LLM, applies the corrected `main.tex`, and recompiles (up to 3
times). The compiler is the kill condition.

```sh
export MD2ARXIV_LLM='claude -p'   # any CLI: reads a prompt on stdin, prints corrected main.tex
```

## Known limits (v1)

- `§(id)` cross-reference tokens are not resolved (they render literally); the
  Astro autonumber plugin does that on the web. A future LLM/polish pass can.
- Figure captions land as body text after the image, not in `\caption{}`.
- Pure-HTML diagram blocks (e.g. an inline colored-span pipeline) are dropped.
- The local tectonic compile is a good proxy for arXiv, not a guarantee; inspect
  `main.pdf` and, on first upload, arXiv's own compile output.

## License

GPL-3.0-or-later. See [LICENSE](LICENSE).
