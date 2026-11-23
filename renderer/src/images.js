// Image source resolution. Local paths are resolved by the Swift host, which owns
// the folder policy and file access; this side only decides what to ask for.
import { escapeHtml } from "./util.js";

let attachments = {};
let remoteImages = false;

/** Whether `https://` images are kept (the app's "Load remote images" setting). */
export function setRemoteImages(enabled) {
  remoteImages = !!enabled;
}

/** Set the current markdown cell's attachments (`attachment:name` references). */
export function setAttachments(a) {
  attachments = a || {};
}

const BLOCKED_REASONS = {
  remote: "Remote image not loaded",
  outsideNotebookFolder: "Image is outside the notebook's folder",
  absolutePath: "Absolute image paths are not loaded",
  missing: "Image not found",
  unsupported: "Unsupported image type",
  tooLarge: "Image too large",
  disabled: "Local images are disabled",
  unreadable: "Image could not be read",
};

function resolve(src) {
  if (src.startsWith("data:image/")) return { src };
  if (src.startsWith("attachment:")) {
    // A malformed name or attachment only loses that image, never the whole notebook.
    let name = src.slice("attachment:".length);
    try {
      name = decodeURIComponent(name);
    } catch (e) {}
    const bundle = attachments[name];
    const mime = bundle && Object.keys(bundle).find((m) => /^image\/[\w.+-]+$/.test(m));
    if (!mime) return { blocked: "missing" };
    const value = bundle[mime];
    const data = Array.isArray(value) ? value.join("") : value;
    if (typeof data !== "string") return { blocked: "unreadable" };
    return { src: `data:${mime};base64,${data.replace(/\s/g, "")}` };
  }
  if (/^https:\/\//i.test(src)) return remoteImages ? { src } : { blocked: "remote" };
  if (/^http:\/\//i.test(src) || src.startsWith("//")) return { blocked: "remote" };
  const host = globalThis.__juprevResolveImage;
  if (typeof host !== "function") return { blocked: "disabled" };
  return JSON.parse(host(src));
}

/**
 * Render an image reference. `originalTag` is a raw <img> from markdown/HTML whose
 * other attributes (width, style…) should be kept when only `src` changes.
 */
export function renderImage(src, alt, title, originalTag) {
  const r = resolve(src);
  if (r.src) {
    // Escape every src: data: URIs from outputs/markdown and https URLs come from the notebook.
    const src = escapeHtml(r.src);
    if (originalTag) return originalTag.replace(/(\bsrc\s*=\s*)(["']).*?\2/i, () => `src="${src}"`);
    const t = title ? ` title="${escapeHtml(title)}"` : "";
    return `<img src="${src}" alt="${escapeHtml(alt || "")}"${t}>`;
  }
  const reason = BLOCKED_REASONS[r.blocked] || "Image not loaded";
  return (
    `<span class="image-placeholder" data-reason="${escapeHtml(r.blocked || "unknown")}" title="${escapeHtml(src)}">` +
    `<span class="image-placeholder-reason">${escapeHtml(reason)}</span>` +
    (alt ? ` <span class="image-placeholder-alt">${escapeHtml(alt)}</span>` : "") +
    `</span>`
  );
}
