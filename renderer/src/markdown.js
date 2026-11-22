// Markdown + TeX rendering. Math is lifted out before markdown-it runs so that
// `_`, `*` and `\\` inside TeX are not mangled into emphasis or escapes.
import MarkdownIt from "markdown-it";
import hljs from "highlight.js/lib/common";
import katex from "katex";
import { escapeHtml } from "./util.js";
import { renderImage } from "./images.js";

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
md.renderer.rules.html_block = (...args) => rewriteRawImages(htmlBlock(...args));
md.renderer.rules.html_inline = (...args) => rewriteRawImages(htmlInline(...args));

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

// Private-use characters: markdown-it rewrites NUL, so it can't be used as a placeholder.
const OPEN = "";
const CLOSE = "";

const CODE_RE = /(^|\n)(```|~~~)[\s\S]*?\n\2|`+[^`\n]*`+/g;
const MATH_RE =
  /(\$\$[\s\S]+?\$\$)|(\\\[[\s\S]+?\\\])|(\\begin\{([a-zA-Z*]+)\}[\s\S]+?\\end\{\4\})|(\\\([\s\S]+?\\\))|((?<![\\$])\$(?![\s$])(?:\\.|[^$\n\\])+?(?<!\s)\$)/g;

export function renderMarkdown(text) {
  const code = [];
  const math = [];
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
    return `${OPEN}M${math.length - 1}${CLOSE}`;
  });
  text = text.replace(new RegExp(`${OPEN}C(\\d+)${CLOSE}`, "g"), (_, i) => code[+i]);
  return md
    .render(text)
    .replace(new RegExp(`${OPEN}M(\\d+)${CLOSE}`, "g"), (_, i) => math[+i]);
}
