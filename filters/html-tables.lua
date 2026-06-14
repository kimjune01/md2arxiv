-- Convert raw-HTML <table> and <figure> blocks into native pandoc elements,
-- so the LaTeX writer renders real tabular/figure environments instead of
-- dropping the raw HTML. Styling (inline CSS) is intentionally discarded;
-- arXiv wants plain LaTeX tables, not styled HTML.
--
-- Figures must already have their <img src> rewritten from /assets/x.svg to a
-- bundle-relative x.pdf (the harness does that before pandoc runs).

function RawBlock(el)
  if el.format == "html" and (el.text:find("<table") or el.text:find("<figure")) then
    local ok, doc = pcall(pandoc.read, el.text, "html")
    if ok then return doc.blocks end
  end
  return nil
end
