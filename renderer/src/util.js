export const escapeHtml = (s) =>
  String(s).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;");

/** nbformat allows multiline strings either as a string or as a list of lines. */
export const joinSource = (src) => (Array.isArray(src) ? src.join("") : src || "");
