# md2arxiv

Turn an Astro/Markdown paper into an arXiv-ready LaTeX **source** bundle and a
reading PDF, both wearing the arXiv-preprint look (kourgeorge/arxiv-style). The
reading PDF *is* the composition's compiled `main.pdf`, so the download and the
submission share one presentation. The translation is deliberately thin:
deterministic code owns arXiv compatibility, an LLM is used only where the input
is messy, and the compiler is the gate. On a judgment call, conform to arXiv
conventions.

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

Input is expected to be clean Markdown (native pipe/grid tables, `![caption](/assets/x.svg)`
figures), not HTML-in-Markdown. pandoc + arxiv-style do the heavy lifting.

**Deterministic (owns arXiv-compat):** pull the abstract into a styled `abstract`;
rasterize referenced SVG figures to vector PDF and point the images at them;
rewrite site-relative links to absolute URLs; resolve `§(id)` cross-refs to
`\ref`; render capability glyphs as symbols (`✓`/`✗` via pifont, `●◐○` Harvey
balls via tikz, each `accsupp`-tagged with `ActualText` so it extracts and reads
as its Unicode char) and fold arrows/comparators to math (`→` `≥` `λ`); merge
heading attributes and shift `##` to `\section`; pandoc emits
`main.tex` with the arxiv-style preamble; arXiv-convention checks (no `.svg`,
bare figure filenames, `\pdfoutput=1`, safe names, every `\includegraphics`
target present); assemble the source-only zip; compile with tectonic as the gate.

**LLM (optional, off by default):** a bounded compile-fix loop. If the bundle
fails to compile and `MD2ARXIV_LLM` is set, the harness feeds the error log plus
`main.tex` to the LLM, applies the corrected `main.tex`, and recompiles (up to 3
times). The compiler is the kill condition.

```sh
export MD2ARXIV_LLM='claude -p'   # any CLI: reads a prompt on stdin, prints corrected main.tex
```

## Known limits (v1)

- HTML blocks are dropped — pandoc cannot render raw HTML into LaTeX. A
  `<figure>`/`<img>` silently loses its image (only the `<figcaption>` text
  survives, as an orphan paragraph), and an HTML `<table>` collapses to a flat
  list. Use markdown instead: `![caption](/assets/x.svg)` for figures (embeds
  with a `\caption{}`) and native pipe tables.
- The local tectonic compile is a good proxy for arXiv, not a guarantee; inspect
  `main.pdf` and, on first upload, arXiv's own compile output.

## License

GPL-3.0-or-later. See [LICENSE](LICENSE).
