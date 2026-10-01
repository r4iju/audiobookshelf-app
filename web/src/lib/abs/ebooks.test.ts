import { describe, expect, it } from "vitest";
import { pageFromLocation, pageProgress, readableEbook } from "./ebooks";
import type { LibraryItem } from "./schemas";

const file = (ino: string, ext: string, isSupplementary: boolean | null) => ({
  ino,
  isSupplementary,
  fileType: "ebook",
  metadata: { filename: `book${ext}`, ext, path: `/books/book${ext}`, size: 1 },
});

const item = (ebook: ReturnType<typeof file> | null, extra: ReturnType<typeof file>[] = []) =>
  ({
    id: "item",
    libraryId: "lib",
    mediaType: "book",
    media: {
      metadata: { title: "Book" },
      tags: [],
      ebookFormat: ebook?.metadata.ext.slice(1),
      ebookFile: ebook,
    },
    libraryFiles: [...(ebook ? [ebook] : []), ...extra],
  }) as unknown as LibraryItem;

describe("readable ebook", () => {
  it("reads the primary ebook and keeps its place on the server", () => {
    expect(readableEbook(item(file("1", ".pdf", null)), null)).toEqual({
      kind: "pdf",
      path: "/api/items/item/ebook",
      keepsProgress: true,
    });
    expect(readableEbook(item(file("1", ".azw3", null)), null)?.kind).toBe("mobi");
    expect(readableEbook(item(file("1", ".cbr", null)), null)?.kind).toBe("comic");
  });

  it("reads a supplementary file by its id without touching the book's place", () => {
    expect(readableEbook(item(file("1", ".epub", null), [file("2", ".PDF", true)]), "2")).toEqual({
      kind: "pdf",
      path: "/api/items/item/ebook/2",
      keepsProgress: false,
    });
  });

  it("has nothing to read for unknown files and formats", () => {
    expect(readableEbook(item(null), null)).toBeNull();
    expect(readableEbook(item(file("1", ".pdf", null)), "9")).toBeNull();
    expect(readableEbook(item(file("1", ".txt", null)), null)).toBeNull();
  });
});

describe("page locations", () => {
  it("resumes at a saved page that exists, and at the first page otherwise", () => {
    expect(pageFromLocation("3", 120)).toBe(3);
    expect(pageFromLocation("121", 120)).toBe(1);
    expect(pageFromLocation("epubcfi(/6/2)", 120)).toBe(1);
    expect(pageFromLocation(null, 120)).toBe(1);
  });

  it("saves the page as text and the share of pages before it", () => {
    expect(pageProgress(3, 120)).toEqual({ ebookLocation: "3", ebookProgress: 2 / 120 });
    expect(pageProgress(1, 1)).toEqual({ ebookLocation: "1", ebookProgress: 0 });
  });
});
