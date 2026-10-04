import "server-only";
import { randomUUID } from "node:crypto";
import { z } from "zod";
import { libraryItemSchema } from "@/lib/abs/schemas";
import { type Account, DomainError } from "./accounts";
import { database, transaction } from "./data";
import { listsChanged, type StoredList, saveImportedList } from "./lists";

export { listImportSchema } from "@/lib/abs/imports";

const id = z.string().min(1).max(256);
const sourceRow = z.record(z.string(), z.union([z.string(), z.number().finite(), z.null()]));
const date = z
  .string()
  .refine((v) => Number.isFinite(Date.parse(v)))
  .transform((v) => Date.parse(v));
function owner(actor: Account) {
  if (!actor.active || actor.type !== "root") throw new DomainError(403, "Owner access required");
}
function inventory(actor: Account, digest: string) {
  owner(actor);
  const db = database();
  if (!db.prepare("SELECT id FROM migrations WHERE digest=? AND scope='media'").get(digest))
    throw new DomainError(409, "Complete the same snapshot's media import first");
  const errors: { table: string; id: string; message: string }[] = [];
  const unsupported: { table: string; id: string; fields: string[] }[] = [];
  const tables = new Map<string, z.infer<typeof sourceRow>[]>();
  for (const table of ["collections", "collectionBooks", "playlists", "playlistMediaItems"]) {
    tables.set(
      table,
      db
        .prepare("SELECT content FROM migration_archive WHERE digest=? AND table_name=? ORDER BY row_key")
        .all(digest, table)
        .map((row) => sourceRow.parse(JSON.parse(z.string().parse(row.content)))),
    );
  }
  const catalog = db
    .prepare("SELECT content FROM catalog_items")
    .all()
    .map((row) => libraryItemSchema.parse(JSON.parse(z.string().parse(row.content))));
  const books = new Map(
    catalog.filter((item) => item.mediaType === "book").map((item) => [item.media.id, item]),
  );
  const episodes = new Map(
    catalog.flatMap((item) => (item.media.episodes ?? []).map((episode) => [episode.id, item] as const)),
  );
  const users = new Set(
    db
      .prepare("SELECT id FROM users")
      .all()
      .map((row) => String(row.id)),
  );
  const lists: StoredList[] = [],
    consumed = new Map<string, Set<string>>();
  const remember = (table: string, key: string) => {
    const values = consumed.get(table) ?? new Set();
    values.add(key);
    consumed.set(table, values);
  };
  for (const [table, kind, join, relation] of [
    ["collections", "collection", "collectionBooks", "collectionId"],
    ["playlists", "playlist", "playlistMediaItems", "playlistId"],
  ] as const) {
    for (const row of tables.get(table) ?? []) {
      try {
        const listId = id.parse(row.id),
          libraryId = id.parse(row.libraryId),
          userId = kind === "collection" ? actor.id : id.parse(row.userId);
        if (!users.has(userId)) throw new Error("Missing original list owner");
        if (!db.prepare("SELECT id FROM libraries WHERE id=?").get(libraryId))
          throw new Error("Missing original library");
        if (db.prepare("SELECT id FROM media_lists WHERE id=?").get(listId))
          throw new Error("Destination list ID already exists");
        const refs = (tables.get(join) ?? [])
          .filter((ref) => ref[relation] === listId)
          .map((ref) => {
            const refId = id.parse(ref.id),
              order = z.number().int().nonnegative().max(100000).parse(ref.order);
            const mediaId = id.parse(kind === "collection" ? ref.bookId : ref.mediaItemId);
            const isEpisode = kind === "playlist" && ref.mediaItemType === "podcastEpisode";
            if (kind === "playlist" && !["book", "podcastEpisode"].includes(String(ref.mediaItemType)))
              throw new Error("Unsupported playlist media type");
            const item = isEpisode ? episodes.get(mediaId) : books.get(mediaId);
            if (!item || item.libraryId !== libraryId)
              throw new Error("Missing or cross-library source membership");
            return { id: refId, order, libraryItemId: item.id, episodeId: isEpisode ? mediaId : null };
          })
          .sort((a, b) => a.order - b.order || a.id.localeCompare(b.id));
        if (refs.length > 10000) throw new Error("List membership exceeds limit");
        if (
          new Set(refs.map((ref) => JSON.stringify([ref.libraryItemId, ref.episodeId]))).size !== refs.length
        )
          throw new Error("Duplicate source membership requires resolution");
        const list: StoredList = {
          id: listId,
          kind,
          libraryId,
          userId,
          name: z.string().trim().min(1).max(256).parse(row.name),
          description: z
            .string()
            .max(16384)
            .nullable()
            .parse(row.description ?? null),
          createdAt: date.parse(row.createdAt),
          updatedAt: date.parse(row.updatedAt),
          entries: refs.map(({ libraryItemId, episodeId }) => ({ libraryItemId, episodeId })),
        };
        lists.push(list);
        remember(table, listId);
        for (const ref of refs) remember(join, ref.id);
      } catch (error) {
        errors.push({
          table,
          id: String(row.id),
          message: error instanceof Error ? error.message : "Invalid source list",
        });
      }
    }
  }
  for (const [table, rows] of tables) {
    const known =
      table === "collections"
        ? ["id", "libraryId", "name", "description", "createdAt", "updatedAt"]
        : table === "playlists"
          ? ["id", "libraryId", "userId", "name", "description", "createdAt", "updatedAt"]
          : table === "collectionBooks"
            ? ["id", "collectionId", "bookId", "order", "createdAt"]
            : ["id", "playlistId", "mediaItemId", "mediaItemType", "order", "createdAt"];
    for (const row of rows) {
      if (!consumed.get(table)?.has(String(row.id)))
        errors.push({ table, id: String(row.id), message: "Unconsumed source list or relationship" });
      const fields = Object.keys(row).filter((field) => !known.includes(field));
      if (fields.length) unsupported.push({ table, id: String(row.id), fields });
    }
  }
  return {
    lists,
    report: {
      digest,
      scope: "lists" as const,
      canImport: errors.length === 0,
      canCutover: false as const,
      counts: {
        collections: lists.filter((l) => l.kind === "collection").length,
        playlists: lists.filter((l) => l.kind === "playlist").length,
        members: lists.reduce((n, l) => n + l.entries.length, 0),
      },
      errors,
      unsupported,
      notices: [
        "Original collections are shared and have no source owner. Shared update/delete permissions manage them. Original playlists retain their account owner.",
        "Unknown source fields remain in the private migration archive; full cutover awaits all remaining domain stages.",
      ],
    },
  };
}
export function inspectLists(actor: Account, digest: string) {
  return inventory(actor, digest).report;
}
export function importLists(actor: Account, digest: string) {
  owner(actor);
  const prior = database()
    .prepare("SELECT content FROM migrations WHERE digest=? AND scope='lists'")
    .get(digest);
  if (prior) return JSON.parse(z.string().parse(prior.content));
  const loaded = inventory(actor, digest);
  if (!loaded.report.canImport) throw new DomainError(409, "Resolve source list errors before import");
  const result = transaction((db) => {
    owner(actor);
    for (const list of loaded.lists) saveImportedList(list);
    const value = {
      id: randomUUID(),
      digest,
      scope: "lists",
      accountCount: new Set(loaded.lists.map((list) => list.userId)).size,
      completedAt: Date.now(),
      report: loaded.report,
    };
    db.prepare("INSERT INTO migrations VALUES(?,?,?,?)").run(
      value.id,
      digest,
      "lists",
      JSON.stringify(value),
    );
    return value;
  });
  listsChanged();
  return result;
}
