// Code cell outputs: streams, rich MIME bundles and errors.
import { ansiToHtml, collapseCarriageReturns } from "./ansi.js";
import { renderMarkdown } from "./markdown.js";
import { renderImage } from "./images.js";
import { escapeHtml, joinSource, stripPageLevelTags } from "./util.js";

const WIDGET_MIME = "application/vnd.jupyter.widget-view+json";
const MIME_ORDER = [
  WIDGET_MIME,
  "text/html",
  "image/svg+xml",
  "image/png",
  "image/jpeg",
  "image/gif",
  "image/webp",
  "text/markdown",
  "text/latex",
  "application/json",
  "text/plain",
];
const STATIC_FALLBACKS = ["image/svg+xml", "image/png", "image/jpeg", "image/gif", "image/webp", "text/plain"];

// Attributes can be separated by "/" as well as whitespace: <img/src=x/onerror=…>.
const looksInteractive = (html) => /<script\b|<iframe\b|<[^>]+[\s/]on[a-z]+\s*=/i.test(html);

export function createOutputRenderer({ allowScripts }) {
  let interactiveOutputs = 0;

  function renderStaticFallback(data, placeholderLabel) {
    const fallback = STATIC_FALLBACKS.find((m) => m in data);
    const placeholder = `<div class="interactive-placeholder">${escapeHtml(placeholderLabel)}</div>`;
    if (!fallback || fallback === "text/plain") {
      // text/plain for widgets/plots is usually a repr like "Figure(...)"; show it under the placeholder.
      const text = fallback ? `<pre class="output-text">${ansiToHtml(joinSource(data[fallback]))}</pre>` : "";
      return placeholder + text;
    }
    return renderMime(fallback, data);
  }

  function renderMime(mime, data) {
    const value = joinSource(data[mime]);
    switch (mime) {
      case WIDGET_MIME:
        interactiveOutputs++;
        return renderStaticFallback(data, "Interactive widget — needs a running kernel");
      case "text/html":
        if (looksInteractive(value)) {
          interactiveOutputs++;
          if (!allowScripts) return renderStaticFallback(data, "Interactive output — scripts are disabled");
        }
        // With scripts allowed, interactive outputs may need their stylesheets (<link>).
        return `<div class="output-html">${allowScripts ? value : stripPageLevelTags(value)}</div>`;
      case "image/svg+xml":
        // As an <img>, scripts inside the SVG never run and its styles can't leak into the page.
        return `<div class="output-image">${renderImage(svgDataURI(value), "")}</div>`;
      case "image/png":
      case "image/jpeg":
      case "image/gif":
      case "image/webp":
        return `<div class="output-image">${renderImage(`data:${mime};base64,${value.replace(/\s/g, "")}`, "")}</div>`;
      case "text/markdown":
        return `<div class="output-markdown">${renderMarkdown(value)}</div>`;
      case "text/latex":
        return `<div class="output-latex">${renderMarkdown(value)}</div>`;
      case "application/json":
        return `<pre class="output-text">${escapeHtml(JSON.stringify(data[mime], null, 2))}</pre>`;
      default:
        return `<pre class="output-text">${ansiToHtml(value)}</pre>`;
    }
  }

  function renderOutput(output) {
    switch (output.output_type) {
      case "stream": {
        const name = output.name === "stderr" ? "stderr" : "stdout";
        return `<pre class="output-stream ${name}">${ansiToHtml(collapseCarriageReturns(joinSource(output.text)))}</pre>`;
      }
      case "execute_result":
      case "display_data": {
        const data = output.data || {};
        const mime = MIME_ORDER.find((m) => m in data);
        return mime ? renderMime(mime, data) : "";
      }
      case "error":
        return `<pre class="output-error">${ansiToHtml((output.traceback || []).join("\n"))}</pre>`;
      default:
        return "";
    }
  }

  return {
    renderOutputs: (outputs) => mergeStreams(outputs || []).map(renderOutput).join(""),
    get interactiveOutputs() {
      return interactiveOutputs;
    },
  };
}

/** Jupyter splits one logical stream into many outputs; merge consecutive ones like the notebook UI does. */
function mergeStreams(outputs) {
  const merged = [];
  for (const o of outputs) {
    const prev = merged[merged.length - 1];
    if (o.output_type === "stream" && prev?.output_type === "stream" && prev.name === o.name) {
      merged[merged.length - 1] = { ...prev, text: joinSource(prev.text) + joinSource(o.text) };
    } else {
      merged.push(o);
    }
  }
  return merged;
}

/**
 * Percent-encode only what a data: URI inside a double-quoted attribute needs.
 * (Base64 would need a hand-written encoder — JavaScriptCore has no btoa — and is slow on multi-MB SVGs.)
 */
function svgDataURI(svg) {
  // Chained literal replaces beat a per-match callback by ~10x on multi-MB inputs.
  const encoded = svg
    .replace(/%/g, "%25").replace(/#/g, "%23").replace(/"/g, "%22").replace(/&/g, "%26")
    .replace(/</g, "%3C").replace(/>/g, "%3E").replace(/\r/g, "%0D").replace(/\n/g, "%0A").replace(/\t/g, "%09");
  return "data:image/svg+xml;charset=utf-8," + encoded;
}
