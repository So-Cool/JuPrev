export const escapeHtml = (s) =>
  String(s).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;");

// Tags that act on the whole page rather than where they appear: <meta http-equiv="refresh">
// can redirect an exported page (CSP has no directive for it), <base> retargets every
// relative link, <link> pulls in remote resources.
const PAGE_LEVEL_TAGS_RE = /<\/?\s*(meta|base|link)\b[^>]*>?/gi;

/** Removes page-level tags, repeating until none are left (so `<met<meta>a …>` can't reassemble one). */
export function stripPageLevelTags(html) {
  let previous;
  do {
    previous = html;
    html = html.replace(PAGE_LEVEL_TAGS_RE, "");
  } while (html !== previous);
  return html;
}

/** nbformat allows multiline strings either as a string or as a list of lines. */
export const joinSource = (src) => (Array.isArray(src) ? src.join("") : src || "");
