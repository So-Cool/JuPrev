// Markdown + TeX rendering. Math is lifted out before markdown-it runs so that
// `_`, `*` and `\\` inside TeX are not mangled into emphasis or escapes.
import MarkdownIt from "markdown-it";
import hljs from "highlight.js/lib/common";
import katex from "katex";
import { escapeHtml, stripPageLevelTags } from "./util.js";
import { renderImage } from "./images.js";

// Private-use characters: markdown-it rewrites NUL, so it can't be used as a placeholder.
const OPEN = "\uE000";
const CLOSE = "\uE001";

const md = new MarkdownIt({
  html: true,
  linkify: true,
  highlight(code, lang) {
    try {
      if (lang && hljs.getLanguage(lang)) return hljs.highlight(code, { language: lang, ignoreIllegals: true }).value;
    } catch (e) {}
    return ""; // markdown-it escapes the code itself
  },
});

// Heading ids follow Jupyter (text with spaces as dashes) so in-notebook links like
// [see](#Training-the-Model) work; the outline sidebar uses them too.
let headings = [];
let usedIds = new Set();
let mathSource = [];
export function resetHeadings() {
  headings = [];
  usedIds = new Set();
}
export const collectedHeadings = () => headings;

md.core.ruler.push("juprev_heading_ids", (state) => {
  const tokens = state.tokens;
  for (let i = 0; i < tokens.length; i++) {
    if (tokens[i].type !== "heading_open") continue;
    const inline = tokens[i + 1];
    const text = (inline.children || [])
      .filter((t) => t.type === "text" || t.type === "code_inline")
      .map((t) => t.content)
      .join("")
      .replace(new RegExp(`${OPEN}M(\\d+)${CLOSE}`, "g"), (m, n) => mathSource[+n] ?? m)
      .trim();
    if (!text) continue;
    // Suffix duplicates (-1, -2, …), skipping ids a later heading already spells out
    // literally: "A", "A", "A-1" become A, A-1, A-1-1.
    const base = text.replace(/\s+/g, "-");
    let id = base;
    for (let n = 1; usedIds.has(id); n++) id = `${base}-${n}`;
    usedIds.add(id);
    tokens[i].attrSet("id", id);
    if (state.env.collectHeadings) headings.push({ level: Number(tokens[i].tag.slice(1)), text, id });
  }
});

md.renderer.rules.image = (tokens, idx) => {
  const token = tokens[idx];
  return renderImage(token.attrGet("src") || "", token.content, token.attrGet("title"));
};

// Raw <img> tags written directly in markdown go through the same resolver.
const IMG_SRC_RE = /(<img\b[^>]*?\bsrc\s*=\s*)(["'])(.*?)\2([^>]*>)/gi;
const rewriteRawImages = (html) =>
  html.replace(IMG_SRC_RE, (tag, _pre, _q, src) => {
    const alt = /\balt\s*=\s*(["'])(.*?)\1/i.exec(tag)?.[2] ?? "";
    return renderImage(src, alt, null, tag);
  });
const htmlBlock = md.renderer.rules.html_block;
const htmlInline = md.renderer.rules.html_inline;
md.renderer.rules.html_block = (...args) => rewriteRawImages(stripPageLevelTags(htmlBlock(...args)));
md.renderer.rules.html_inline = (...args) => rewriteRawImages(stripPageLevelTags(htmlInline(...args)));

// Like MathJax in Jupyter, \newcommand in one cell is visible in later cells.
let macros = {};
export function resetMacros() {
  macros = {};
}

/** Built-in KaTeX command or a macro defined earlier in this notebook? */
function isDefined(name) {
  if (name in macros) return true;
  try {
    katex.renderToString(name, { throwOnError: true });
    return true;
  } catch (e) {
    return !/Undefined control sequence/.test(e.message);
  }
}

// MathJax accepts some TeX that KaTeX rejects; retry with these rewrites before giving up.
const LENIENT_REWRITES = [
  // MathJax's \newcommand and \renewcommand both just define; KaTeX insists on the right one.
  [/\\(?:re)?newcommand\s*\{?\s*(\\[a-zA-Z]+)\s*\}?/g, (_, name) => `\\${isDefined(name) ? "renew" : "new"}command{${name}}`],
  // f_\mathring{c} -> f_{\mathring{c}}
  [/([_^])\s*(\\[a-zA-Z]+\{[^{}]*\})/g, "$1{$2}"],
];

const katexOptions = (displayMode) => ({
  displayMode,
  throwOnError: true,
  output: "html",
  trust: false,
  strict: "ignore",
  macros,
  globalGroup: true,
});

export function renderTex(tex, displayMode) {
  // A failed render may already have defined some macros; roll those back before retrying.
  const before = { ...macros };
  try {
    return katex.renderToString(tex, katexOptions(displayMode));
  } catch (error) {
    macros = { ...before };
    const lenient = LENIENT_REWRITES.reduce((t, [re, to]) => t.replace(re, to), tex);
    if (lenient !== tex) {
      try {
        return katex.renderToString(lenient, katexOptions(displayMode));
      } catch (e) {
        macros = before;
      }
    }
    const message = error instanceof katex.ParseError ? error.message : String(error);
    return `<span class="katex-error" title="${escapeHtml(message)}">${escapeHtml(tex)}</span>`;
  }
}


// Fenced code (also indented, e.g. inside list items) and inline code. Like Jupyter's own
// math extraction, 4-space indented code blocks aren't recognised.
const CODE_RE = /(^|\n)([ \t]*)(```|~~~)[\s\S]*?\n\2\3|`+[^`\n]*`+/g;
const MATH_RE =
  /(\$\$[\s\S]+?\$\$)|(\\\[[\s\S]+?\\\])|(\\begin\{([a-zA-Z*]+)\}[\s\S]+?\\end\{\4\})|(\\\([\s\S]+?\\\))|((?<![\\$])\$(?![\s$])(?:\\.|[^$\n\\])+?(?<!\s)\$)/g;

/** `collectHeadings`: add this text's headings to the outline (markdown cells, not outputs). */
export function renderMarkdown(text, { collectHeadings = false } = {}) {
  const code = [];
  const math = [];
  mathSource = [];
  text = text.replace(CODE_RE, (m) => {
    code.push(m);
    return `${OPEN}C${code.length - 1}${CLOSE}`;
  });
  text = text.replace(MATH_RE, (m, dd, sq, env, _envName, paren, single) => {
    const html =
      dd ? renderTex(dd.slice(2, -2), true) :
      sq ? renderTex(sq.slice(2, -2), true) :
      env ? renderTex(env, true) :
      paren ? renderTex(paren.slice(2, -2), false) :
      renderTex(single.slice(1, -1), false);
    math.push(html);
    // Shown in the outline as plain TeX, without the $…$ / \(…\) delimiters.
    mathSource.push(m.replace(/^\$+|\$+$/g, "").replace(/^\\[([]|\\[)\]]$/g, ""));
    return `${OPEN}M${math.length - 1}${CLOSE}`;
  });
  text = text.replace(new RegExp(`${OPEN}C(\\d+)${CLOSE}`, "g"), (m, i) => code[+i] ?? m);
  return md
    .render(text, { collectHeadings })
    .replace(new RegExp(`${OPEN}M(\\d+)${CLOSE}`, "g"), (m, i) => math[+i] ?? m);
}
