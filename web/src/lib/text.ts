const entities: Record<string, string> = {
  amp: "&",
  lt: "<",
  gt: ">",
  quot: '"',
  apos: "'",
  nbsp: " ",
  "#39": "'",
};

/** Server descriptions may be HTML from metadata providers; this client shows them as plain text, never as markup. */
export function htmlToText(html: string | null | undefined) {
  if (!html) return "";
  return html
    .replace(/<\s*br\s*\/?>/gi, "\n")
    .replace(/<\/\s*(p|div|li|h[1-6])\s*>/gi, "\n")
    .replace(/<[^>]*>/g, "")
    .replace(/&(#\d+|#x[\da-f]+|[a-z]+);/gi, (match, name: string) => {
      if (name.startsWith("#x") || name.startsWith("#X"))
        return String.fromCodePoint(Number.parseInt(name.slice(2), 16));
      if (name.startsWith("#") && name !== "#39") return String.fromCodePoint(Number(name.slice(1)));
      return entities[name.toLowerCase()] ?? match;
    })
    .replace(/\n{3,}/g, "\n\n")
    .trim();
}
