// Minimal ANSI SGR -> HTML for streams and tracebacks.
import { escapeHtml } from "./util.js";

const COLORS = ["black", "red", "green", "yellow", "blue", "magenta", "cyan", "white"];

/** Emulate carriage returns (progress bars): keep only the text after the last `\r` on each line. */
export function collapseCarriageReturns(text) {
  return text
    .replace(/\r\n/g, "\n")
    .split("\n")
    .map((line) => line.slice(line.lastIndexOf("\r") + 1))
    .join("\n");
}

export function ansiToHtml(text) {
  let out = "";
  let open = 0;
  const parts = escapeHtml(text).split(/\x1b\[([\d;]*)m/);
  for (let i = 0; i < parts.length; i++) {
    if (i % 2 === 0) {
      out += parts[i];
      continue;
    }
    const codes = parts[i] === "" ? [0] : parts[i].split(";").map(Number);
    for (let j = 0; j < codes.length; j++) {
      const c = codes[j];
      if (c === 0) {
        out += "</span>".repeat(open);
        open = 0;
      } else if (c === 38 || c === 48) {
        // Extended colours (5;n or 2;r;g;b) are skipped rather than mis-parsed.
        j += codes[j + 1] === 5 ? 2 : codes[j + 1] === 2 ? 4 : 0;
      } else {
        const cls =
          c >= 30 && c <= 37 ? `ansi-${COLORS[c - 30]}-fg` :
          c >= 90 && c <= 97 ? `ansi-${COLORS[c - 90]}-fg ansi-bright` :
          c >= 40 && c <= 47 ? `ansi-${COLORS[c - 40]}-bg` :
          c === 1 ? "ansi-bold" :
          c === 3 ? "ansi-italic" :
          c === 4 ? "ansi-underline" : null;
        if (cls) {
          out += `<span class="${cls}">`;
          open++;
        }
      }
    }
  }
  return out + "</span>".repeat(open);
}
