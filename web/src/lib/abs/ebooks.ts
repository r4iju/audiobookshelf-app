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

export interface MobiPlace {
  section: number;
  /** The first text block showing at the top, so the same passage returns at any window size. */
  block: number;
}

/**
 * The legacy clients never saved a MOBI place, so this format is the browser's own:
 * `mobi:{version}:{section}:{block}`. Sections come from how foliate-js splits the file and blocks from the
 * reader's block selector; the version changes with either, so an older place opens at the start instead of
 * at the wrong passage. A place saved by another format reads as none.
 */
const MOBI_PLACE_VERSION = 1;

export function mobiPlace(location: string | null | undefined): MobiPlace | null {
  const match = location?.match(/^mobi:(\d+):(\d+):(\d+)$/);
  if (!match || Number(match[1]) !== MOBI_PLACE_VERSION) return null;
  return { section: Number(match[2]), block: Number(match[3]) };
}

export const mobiLocation = ({ section, block }: MobiPlace) =>
  `mobi:${MOBI_PLACE_VERSION}:${section}:${block}`;

/** The share of the book's text read, given each section's size and the share of this one read. */
export function mobiProgress(sizes: number[], section: number, fraction: number) {
  const total = sizes.reduce((sum, size) => sum + size, 0);
  if (!total) return 0;
  const before = sizes.slice(0, section).reduce((sum, size) => sum + size, 0);
  return Math.min(1, Math.max(0, (before + fraction * (sizes[section] ?? 0)) / total));
}
