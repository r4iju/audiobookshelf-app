import type { ReaderSettings } from "@/lib/settings/store";

export const readerThemes: Record<ReaderSettings["theme"], { color: string; background: string }> = {
  dark: { color: "#fff", background: "rgb(35, 35, 35)" },
  black: { color: "#fff", background: "rgb(0, 0, 0)" },
  light: { color: "#000", background: "rgb(255, 255, 255)" },
};

/** The legacy reader's colour, spacing and boldness rules, so a book looks the same in every client. */
export function readerCss(settings: ReaderSettings) {
  const { color, background } = readerThemes[settings.theme];
  return `* { color: ${color} !important; background-color: ${background} !important; line-height: ${settings.lineSpacing}% !important; -webkit-text-stroke: ${settings.textStroke / 100}px ${color} !important; }
a { color: ${color} !important; }`;
}

/** epub.js's theme rules can only be added to, never replaced, so the reader's rules live in one style element per document. */
export function applyReaderCss(document: Document, css: string) {
  let style = document.getElementById("abs-reader-theme");
  if (!style) {
    style = document.createElement("style");
    style.id = "abs-reader-theme";
    document.head.append(style);
  }
  style.textContent = css;
}
