import { z } from "zod";
import { readStored, removeStored, storedKeys, writeStored } from "./local";

const PREFIX = "abs-web:v1:epub-locations:";
const KEPT_BOOKS = 10;
const entrySchema = z.object({ locations: z.string(), at: z.number() });

/** An EPUB's generated locations, kept for the books opened most recently in this browser. */
export function storedLocations(book: string) {
  const entry = readStored(PREFIX + book, entrySchema);
  if (entry) writeStored(PREFIX + book, { ...entry, at: Date.now() });
  return entry?.locations ?? null;
}

export function keepLocations(book: string, locations: string) {
  const older = storedKeys(PREFIX)
    .filter((key) => key !== PREFIX + book)
    .map((key) => ({ key, at: readStored(key, entrySchema)?.at ?? 0 }))
    .sort((a, b) => b.at - a.at);
  for (const { key } of older.slice(KEPT_BOOKS - 1)) removeStored(key);
  try {
    writeStored(PREFIX + book, { locations, at: Date.now() });
  } catch {
    // A full storage quota only costs generating the locations again next time.
  }
}
