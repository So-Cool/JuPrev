// Entry point: exposes NBRender.renderNotebook(json, optionsJSON) -> resultJSON.
// Runs in a bare JavaScriptCore context (no DOM, no window).
import hljs from "highlight.js/lib/common";
import { collectedHeadings, renderMarkdown, resetHeadings, resetMacros } from "./markdown.js";
import { createOutputRenderer } from "./outputs.js";
import { blockedImages, resetBlockedImages, setAttachments, setRemoteImages } from "./images.js";
import { escapeHtml, joinSource } from "./util.js";

function highlight(code, lang) {
  try {
    if (lang && hljs.getLanguage(lang)) return hljs.highlight(code, { language: lang, ignoreIllegals: true }).value;
  } catch (e) {}
  return escapeHtml(code);
}

/** metadata.title, else the first level-1 heading (as markdown-it parsed it, so code is ignored). */
function notebookTitle(nb, headings) {
  if (typeof nb.metadata?.title === "string" && nb.metadata.title) return nb.metadata.title;
  return headings.find((h) => h.level === 1)?.text ?? null;
}

/** Errors with a `code` are reported to Swift as typed failures rather than generic exceptions. */
function fail(code, message) {
  const e = new Error(message);
  e.code = code;
  throw e;
}

export function renderNotebook(jsonText, optionsJSON) {
  const options = JSON.parse(optionsJSON || "{}");
  let nb;
  try {
    nb = JSON.parse(jsonText);
  } catch (e) {
    fail("invalidJSON", e.message);
  }
  if (typeof nb !== "object" || nb === null) fail("invalidJSON", "Notebook is not a JSON object");
  if (nb.nbformat !== 4) fail("unsupportedFormat", String(nb.nbformat ?? "unknown"));
  if (!Array.isArray(nb.cells)) fail("invalidJSON", "Notebook has no cells array");

  const language =
    nb.metadata?.language_info?.name || nb.metadata?.kernelspec?.language || "python";
  const outputs = createOutputRenderer({ allowScripts: !!options.allowScripts });
  resetMacros();
  resetHeadings();
  setRemoteImages(options.remoteImages);
  resetBlockedImages();

  const html = nb.cells
    .map((cell) => {
      const src = joinSource(cell.source);
      switch (cell.cell_type) {
        case "markdown":
          setAttachments(cell.attachments);
          try {
            return `<section class="cell markdown">${renderMarkdown(src, { collectHeadings: true })}</section>`;
          } finally {
            setAttachments(null);
          }
        case "code": {
          const count = cell.execution_count ?? " ";
          const out = outputs.renderOutputs(cell.outputs);
          return (
            `<section class="cell code">` +
            `<div class="input"><span class="prompt">[${escapeHtml(String(count))}]</span>` +
            `<pre class="source"><code class="hljs language-${escapeHtml(language)}">${highlight(src, language)}</code></pre></div>` +
            (out ? `<div class="outputs">${out}</div>` : "") +
            `</section>`
          );
        }
        default:
          return `<section class="cell raw"><pre>${escapeHtml(src)}</pre></section>`;
      }
    })
    .join("\n");

  return JSON.stringify({
    html,
    title: notebookTitle(nb, collectedHeadings()),
    language,
    cellCount: nb.cells.length,
    interactiveOutputs: outputs.interactiveOutputs,
    headings: collectedHeadings(),
    blockedImages: blockedImages(),
  });
}
