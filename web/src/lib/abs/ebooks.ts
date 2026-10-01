import type { LibraryItem } from "./schemas";

export type EbookKind = "epub" | "mobi" | "pdf" | "comic";

const kinds: Record<string, EbookKind> = {
  epub: "epub",
  mobi: "mobi",
  azw3: "mobi",
  pdf: "pdf",
  cbz: "comic",
  cbr: "comic",
};

export interface ReadableEbook {
  kind: EbookKind;
  path: string;
  /** Supplementary files are read without moving the book's saved place, as in the legacy client. */
  keepsProgress: boolean;
}

/** The book's own ebook, or the ebook library file with the given id. */
export function readableEbook(item: LibraryItem, fileIno: string | null): ReadableEbook | null {
  const file = fileIno
    ? item.libraryFiles?.find((entry) => entry.ino === fileIno && entry.fileType === "ebook")
    : item.media.ebookFile;
  if (!file) return null;
  const kind = kinds[file.metadata.ext.replace(/^\./, "").toLowerCase()];
  if (!kind) return null;
  return fileIno
    ? { kind, path: `/api/items/${item.id}/ebook/${fileIno}`, keepsProgress: false }
    : { kind, path: `/api/items/${item.id}/ebook`, keepsProgress: true };
}

/** PDFs and comics save their 1-based page as text, as the other clients do. */
export function pageFromLocation(location: string | null | undefined, pages: number) {
  const page = Number(location);
  return Number.isInteger(page) && page >= 1 && page <= pages ? page : 1;
}

export function pageProgress(page: number, pages: number) {
  return { ebookLocation: String(page), ebookProgress: Math.min(1, Math.max(0, (page - 1) / pages)) };
}
