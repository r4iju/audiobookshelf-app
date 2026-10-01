import type { z } from "zod";

/** Browser storage is untrusted input (older versions, other tabs, manual edits): every read goes through a schema. */
export function readStored<T extends z.ZodType>(key: string, schema: T): z.infer<T> | null {
  if (typeof localStorage === "undefined") return null;
  const raw = localStorage.getItem(key);
  if (raw === null) return null;
  try {
    const parsed = schema.safeParse(JSON.parse(raw));
    return parsed.success ? parsed.data : null;
  } catch {
    return null;
  }
}

export function writeStored(key: string, value: unknown) {
  localStorage.setItem(key, JSON.stringify(value));
}

export function removeStored(key: string) {
  localStorage.removeItem(key);
}

export function storedKeys(prefix: string) {
  return Object.keys(localStorage).filter((key) => key.startsWith(prefix));
}
