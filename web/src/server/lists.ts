import "server-only";
import { randomUUID } from "node:crypto";
import { z } from "zod";
import { collectionSchema, type LibraryItem, playlistSchema } from "@/lib/abs/schemas";
import { type Account, canReadLibrary, DomainError, permissions } from "./accounts";
import { findLibrary, itemFor } from "./catalog";
import { database, transaction } from "./data";

const id = z.string().min(1).max(256);
const entry = z.object({ libraryItemId: id, episodeId: id.nullish() });
const members = z.array(entry).max(10000);
const fields = {
  name: z.string().trim().min(1).max(256),
  description: z.string().max(16384).nullable().optional(),
};
export const createListSchema = z.object({
  libraryId: id,
  ...fields,
  books: z.array(id).max(10000).optional(),
  items: members.optional(),
});
export const editListSchema = z.object({
  name: fields.name.optional(),
  description: fields.description,
  books: z.array(id).max(10000).optional(),
  items: members.optional(),
});
export const listBatchSchema = z.object({
  books: z.array(id).max(10000).optional(),
  items: members.optional(),
});
export const storedSchema = z.object({
  id,
  kind: z.enum(["collection", "playlist"]),
  libraryId: id,
  userId: id,
  name: fields.name,
  description: z.string().nullable(),
  entries: members,
  createdAt: z.number(),
  updatedAt: z.number(),
});
export type StoredList = z.infer<typeof storedSchema>;
export type ListKind = StoredList["kind"];
function library(actor: Account, libraryId: string) {
  if (!actor.active || !canReadLibrary(actor, libraryId)) throw new DomainError(404, "Not found");
  return findLibrary(libraryId);
}
function row(id: string, kind: ListKind) {
  const found = database().prepare("SELECT content FROM media_lists WHERE id=? AND kind=?").get(id, kind);
  if (!found) throw new DomainError(404, "Not found");
  return storedSchema.parse(JSON.parse(z.string().parse(found.content)));
}
function accessible(actor: Account, list: StoredList) {
  library(actor, list.libraryId);
  if (list.kind === "playlist" && list.userId !== actor.id) throw new DomainError(404, "Not found");
}
function expanded(actor: Account, list: StoredList, catalog?: Map<string, LibraryItem>) {
  accessible(actor, list);
  const entries = list.entries.flatMap((ref) => {
    let item: LibraryItem;
    try {
      if (catalog) {
        const found = catalog.get(ref.libraryItemId);
        if (!found) return [];
        item = found;
      } else item = itemFor(actor, ref.libraryItemId);
    } catch (error) {
      if (error instanceof DomainError && error.status === 404) return [];
      throw error;
    }
    if (item.libraryId !== list.libraryId) return [];
    const episode = ref.episodeId ? item.media.episodes?.find((e) => e.id === ref.episodeId) : undefined;
    if (ref.episodeId && !episode) return [];
    return [
      {
        libraryItemId: item.id,
        episodeId: ref.episodeId ?? null,
        libraryItem: item,
        ...(episode ? { episode } : {}),
      },
    ];
  });
  const common = {
    id: list.id,
    userId: list.userId,
    libraryId: list.libraryId,
    name: list.name,
    description: list.description,
    createdAt: list.createdAt,
    updatedAt: list.updatedAt,
  };
  return list.kind === "collection"
    ? collectionSchema.parse({ ...common, books: entries.map((ref) => ref.libraryItem) })
    : playlistSchema.parse({ ...common, userId: list.userId, items: entries });
}
export function listFor(actor: Account, kind: ListKind, id: string) {
  return expanded(actor, row(id, kind));
}
export function listsFor(actor: Account, kind: ListKind, libraryId: string, params = new URLSearchParams()) {
  library(actor, libraryId);
  const lists = database()
    .prepare("SELECT content FROM media_lists WHERE kind=? AND library_id=? ORDER BY created_at,id")
    .all(kind, libraryId)
    .map((record) => storedSchema.parse(JSON.parse(z.string().parse(record.content))))
    .filter((list) => kind === "collection" || list.userId === actor.id);
  const limit = z.coerce
    .number()
    .int()
    .min(1)
    .max(10000)
    .parse(params.get("limit") ?? 10000);
  const page = z.coerce
    .number()
    .int()
    .min(0)
    .max(100000)
    .parse(params.get("page") ?? 0);
  return {
    results: lists.slice(page * limit, (page + 1) * limit).map((list) => expanded(actor, list)),
    total: lists.length,
    limit,
    page,
  };
}
export function allListsFor(actor: Account, kind: ListKind) {
  return database()
    .prepare(
      "SELECT content FROM media_lists WHERE kind=? AND (?='collection' OR user_id=?) ORDER BY created_at,id",
    )
    .all(kind, kind, actor.id)
    .flatMap((record) => {
      const list = storedSchema.parse(JSON.parse(z.string().parse(record.content)));
      try {
        return [expanded(actor, list)];
      } catch (error) {
        if (error instanceof DomainError && error.status === 404) return [];
        throw error;
      }
    });
}
function normalize(
  actor: Account,
  kind: ListKind,
  libraryId: string,
  input: z.infer<typeof listBatchSchema>,
) {
  const values =
    kind === "collection"
      ? (input.books ?? []).map((libraryItemId) => ({ libraryItemId, episodeId: null }))
      : (input.items ?? []);
  const unique = new Map<string, z.infer<typeof entry>>();
  for (const ref of values) {
    const item = itemFor(actor, ref.libraryItemId);
    if (item.libraryId !== libraryId || (kind === "collection" && item.mediaType !== "book"))
      throw new DomainError(400, "List members must belong to its library");
    if (ref.episodeId && !item.media.episodes?.some((e) => e.id === ref.episodeId))
      throw new DomainError(404, "Not found");
    if (item.mediaType === "podcast" && !ref.episodeId)
      throw new DomainError(400, "Select a podcast episode");
    const value = { libraryItemId: item.id, episodeId: ref.episodeId ?? null };
    unique.set(JSON.stringify([value.libraryItemId, value.episodeId]), value);
  }
  return [...unique.values()];
}
function writable(actor: Account, list: StoredList, action: "update" | "delete" = "update") {
  accessible(actor, list);
  if (list.kind === "collection" && !permissions.parse(JSON.parse(actor.permissions))[action])
    throw new DomainError(403, "Your account cannot change shared collections");
}
export function saveImportedList(list: StoredList) {
  const value = storedSchema.parse(list);
  database()
    .prepare("INSERT INTO media_lists VALUES(?,?,?,?,?,?)")
    .run(value.id, value.kind, value.libraryId, value.userId, value.createdAt, JSON.stringify(value));
}
declare global {
  var leafwakeListsRevision: number | undefined;
}
export function listsChanged() {
  globalThis.leafwakeListsRevision = (globalThis.leafwakeListsRevision ?? 0) + 1;
  globalThis.leafwakeRealtimeChanged?.({ lists: true });
}
export function createList(actor: Account, kind: ListKind, input: z.infer<typeof createListSchema>) {
  library(actor, input.libraryId);
  if (kind === "collection" && !permissions.parse(JSON.parse(actor.permissions)).update)
    throw new DomainError(403, "Your account cannot create shared collections");
  const result = transaction(() => {
    const list: StoredList = {
      id: randomUUID(),
      kind,
      libraryId: input.libraryId,
      userId:
        kind === "collection"
          ? z.string().parse(database().prepare("SELECT id FROM users WHERE type='root' LIMIT 1").get()?.id)
          : actor.id,
      name: input.name,
      description: input.description ?? null,
      entries: normalize(actor, kind, input.libraryId, input),
      createdAt: Date.now(),
      updatedAt: Date.now(),
    };
    saveImportedList(list);
    return list;
  });
  listsChanged();
  return expanded(actor, result);
}
export function changeList(
  actor: Account,
  kind: ListKind,
  id: string,
  input: z.infer<typeof editListSchema>,
  operation: "edit" | "add" | "remove" = "edit",
) {
  const result = transaction((db) => {
    const list = row(id, kind);
    writable(actor, list);
    if (operation === "edit") {
      if (input.name !== undefined) list.name = input.name;
      if (input.description !== undefined) list.description = input.description;
      if (input.books !== undefined || input.items !== undefined) {
        const replacements = normalize(actor, kind, list.libraryId, input);
        const retained = list.entries.map((ref) => {
          try {
            const item = itemFor(actor, ref.libraryItemId);
            return (
              item.libraryId !== list.libraryId ||
              Boolean(ref.episodeId && !item.media.episodes?.some((e) => e.id === ref.episodeId))
            );
          } catch (error) {
            if (error instanceof DomainError && error.status === 404) return true;
            throw error;
          }
        });
        // Native metadata/reorder saves contain only visible members. Hidden references keep their slots.
        let position = 0;
        list.entries = list.entries.flatMap((ref, index) => {
          if (retained[index]) return [ref];
          const replacement = replacements[position];
          if (!replacement) return [];
          position++;
          return [replacement];
        });
        list.entries.push(...replacements.slice(position));
      }
    } else {
      // Removing inaccessible old references is safe; adding requires current media authority.
      const refs =
        operation === "add"
          ? normalize(actor, kind, list.libraryId, input)
          : kind === "collection"
            ? (input.books ?? []).map((libraryItemId) => ({ libraryItemId, episodeId: null }))
            : (input.items ?? []);
      const keys = new Set(refs.map((ref) => JSON.stringify([ref.libraryItemId, ref.episodeId ?? null])));
      if (operation === "remove")
        list.entries = list.entries.filter(
          (ref) => !keys.has(JSON.stringify([ref.libraryItemId, ref.episodeId ?? null])),
        );
      else {
        const existing = new Set(
          list.entries.map((ref) => JSON.stringify([ref.libraryItemId, ref.episodeId ?? null])),
        );
        list.entries.push(
          ...refs.filter((ref) => !existing.has(JSON.stringify([ref.libraryItemId, ref.episodeId ?? null]))),
        );
      }
    }
    if (list.entries.length > 10000) throw new DomainError(400, "List membership limit exceeded");
    list.updatedAt = Date.now();
    if (kind === "playlist" && list.entries.length === 0)
      db.prepare("DELETE FROM media_lists WHERE id=?").run(id);
    else db.prepare("UPDATE media_lists SET content=? WHERE id=?").run(JSON.stringify(list), id);
    return list;
  });
  listsChanged();
  return expanded(actor, result);
}
export function deleteList(actor: Account, kind: ListKind, id: string) {
  transaction((db) => {
    writable(actor, row(id, kind), "delete");
    db.prepare("DELETE FROM media_lists WHERE id=?").run(id);
  });
  listsChanged();
}
type RealtimeList = { kind: ListKind; value: ReturnType<typeof expanded> };
const snapshots = new Map<string, { revision: string; values: RealtimeList[] }>();
export function realtimeLists(actor: Account, items: LibraryItem[]) {
  const key = JSON.stringify([actor.id, actor.permissions, actor.libraries, actor.tags]);
  const revision = `${globalThis.leafwakeCatalogRevision ?? 0}:${globalThis.leafwakeListsRevision ?? 0}`;
  const cached = snapshots.get(key);
  if (cached?.revision === revision) return cached.values;
  // Realtime catalogs omit per-user progress generations; progress/reset events carry their own authority.
  const catalog = new Map(items.map((item) => [item.id, item]));
  const values: RealtimeList[] = database()
    .prepare("SELECT content FROM media_lists WHERE kind='collection' OR user_id=? ORDER BY id")
    .all(actor.id)
    .flatMap((record) => {
      const list = storedSchema.parse(JSON.parse(z.string().parse(record.content)));
      try {
        return [{ kind: list.kind, value: expanded(actor, list, catalog) }];
      } catch (error) {
        if (error instanceof DomainError && error.status === 404) return [];
        throw error;
      }
    });
  if (snapshots.size >= 256) snapshots.clear();
  snapshots.set(key, { revision, values });
  return values;
}
