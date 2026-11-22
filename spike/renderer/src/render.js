// Spike renderer: notebook JSON string -> static HTML fragment.
// Runs in a bare JavaScriptCore context (no DOM, no window).
import MarkdownIt from "markdown-it";
import katex from "katex";
import hljs from "highlight.js/lib/common";

const md = new MarkdownIt({ html: true, linkify: true });

const escapeHtml = (s) =>
  s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;");

const joinSource = (src) => (Array.isArray(src) ? src.join("") : src || "");

function renderTex(tex, displayMode) {
  try {
    return katex.renderToString(tex, { displayMode, throwOnError: false, output: "html" });
  } catch (e) {
    return `<code class="math-error">${escapeHtml(tex)}</code>`;
  }
}

// Pull math out before markdown-it sees it, so `_` and `*` inside TeX survive.
const MATH_RE =
  /(\$\$[\s\S]+?\$\$)|(\\\[[\s\S]+?\\\])|(\\begin\{([a-z*]+)\}[\s\S]+?\\end\{\4\})|(\\\([\s\S]+?\\\))|(\$(?!\s)(?:\\.|[^$\n\\])+?\$)/g;

function renderMarkdown(text) {
  const stash = [];
  // Protect fenced/inline code from math extraction.
  const codeStash = [];
  text = text.replace(/(```[\s\S]*?```|`[^`\n]*`)/g, (m) => {
    codeStash.push(m);
    return `\uE000C${codeStash.length - 1}\uE001`;
  });
  text = text.replace(MATH_RE, (m, dd, sq, env, _envName, paren, single) => {
    let html;
    if (dd) html = renderTex(dd.slice(2, -2), true);
    else if (sq) html = renderTex(sq.slice(2, -2), true);
    else if (env) html = renderTex(env, true);
    else if (paren) html = renderTex(paren.slice(2, -2), false);
    else html = renderTex(single.slice(1, -1), false);
    stash.push(html);
    return `\uE000M${stash.length - 1}\uE001`;
  });
  text = text.replace(/\uE000C(\d+)\uE001/g, (_, i) => codeStash[+i]);
  let html = md.render(text);
  return html.replace(/\uE000M(\d+)\uE001/g, (_, i) => stash[+i]);
}

function highlight(code, lang) {
  try {
    if (lang && hljs.getLanguage(lang)) return hljs.highlight(code, { language: lang }).value;
  } catch (e) {}
  return escapeHtml(code);
}

const ANSI_COLORS = ["black", "red", "green", "yellow", "blue", "magenta", "cyan", "white"];
function ansiToHtml(text) {
  let out = "";
  let open = 0;
  const parts = escapeHtml(text).split(/\x1b\[([\d;]*)m/);
  for (let i = 0; i < parts.length; i++) {
    if (i % 2 === 0) { out += parts[i]; continue; }
    const codes = parts[i].split(";").filter(Boolean).map(Number);
    if (codes.length === 0 || codes.includes(0)) { out += "</span>".repeat(open); open = 0; }
    for (const c of codes) {
      if (c >= 30 && c <= 37) { out += `<span class="ansi-${ANSI_COLORS[c - 30]}-fg">`; open++; }
      else if (c >= 40 && c <= 47) { out += `<span class="ansi-${ANSI_COLORS[c - 40]}-bg">`; open++; }
      else if (c === 1) { out += `<span class="ansi-bold">`; open++; }
    }
  }
  return out + "</span>".repeat(open);
}

const MIME_ORDER = [
  "application/vnd.jupyter.widget-view+json",
  "text/html", "image/svg+xml", "image/png", "image/jpeg", "image/gif",
  "text/markdown", "text/latex", "text/plain",
];

let interactiveCount = 0;

function renderMimeBundle(data) {
  const mime = MIME_ORDER.find((m) => m in data);
  if (!mime) return "";
  const v = joinSource(data[mime]);
  switch (mime) {
    case "application/vnd.jupyter.widget-view+json":
      interactiveCount++;
      if ("image/png" in data) return renderMimeBundle({ "image/png": data["image/png"] });
      return `<div class="interactive-placeholder">Interactive widget (not rendered)</div>`;
    case "text/html":
      if (/<script/i.test(v)) {
        interactiveCount++;
        // Prefer a static fallback if the kernel also emitted one.
        if ("image/png" in data) return renderMimeBundle({ "image/png": data["image/png"] });
      }
      return `<div class="output-html">${v}</div>`;
    case "image/svg+xml":
      return `<div class="output-image">${v}</div>`;
    case "image/png": case "image/jpeg": case "image/gif":
      return `<div class="output-image"><img src="data:${mime};base64,${v.replace(/\n/g, "")}"></div>`;
    case "text/markdown":
      return `<div class="output-markdown">${renderMarkdown(v)}</div>`;
    case "text/latex":
      return `<div class="output-latex">${renderMarkdown(v)}</div>`;
    default:
      return `<pre class="output-text">${ansiToHtml(v)}</pre>`;
  }
}

function renderOutput(o) {
  switch (o.output_type) {
    case "stream":
      return `<pre class="output-stream ${o.name}">${ansiToHtml(joinSource(o.text))}</pre>`;
    case "execute_result": case "display_data":
      return renderMimeBundle(o.data || {});
    case "error":
      return `<pre class="output-error">${ansiToHtml((o.traceback || []).join("\n"))}</pre>`;
    default:
      return "";
  }
}

function renderAttachments(src, attachments) {
  if (!attachments) return src;
  return src.replace(/attachment:([^\s)"']+)/g, (m, name) => {
    const bundle = attachments[name];
    if (!bundle) return m;
    const mime = Object.keys(bundle)[0];
    return `data:${mime};base64,${joinSource(bundle[mime]).replace(/\n/g, "")}`;
  });
}

export function renderNotebook(jsonText) {
  interactiveCount = 0;
  const nb = JSON.parse(jsonText);
  if (nb.nbformat !== 4) throw new Error(`Unsupported nbformat ${nb.nbformat}`);
  const lang =
    nb.metadata?.language_info?.name || nb.metadata?.kernelspec?.language || "python";
  const cells = nb.cells.map((cell) => {
    const src = joinSource(cell.source);
    if (cell.cell_type === "markdown") {
      return `<section class="cell markdown">${renderMarkdown(renderAttachments(src, cell.attachments))}</section>`;
    }
    if (cell.cell_type === "code") {
      const count = cell.execution_count ?? " ";
      const outputs = (cell.outputs || []).map(renderOutput).join("");
      return `<section class="cell code"><div class="prompt">[${count}]</div>` +
        `<pre class="source hljs"><code>${highlight(src, lang)}</code></pre>` +
        (outputs ? `<div class="outputs">${outputs}</div>` : "") + `</section>`;
    }
    return `<section class="cell raw"><pre>${escapeHtml(src)}</pre></section>`;
  });
  return JSON.stringify({ html: cells.join("\n"), interactiveCount });
}
