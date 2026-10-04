import "server-only";
import { randomUUID } from "node:crypto";
import { z } from "zod";
import { bookmarkSchema } from "@/lib/abs/schemas";
import { type Account, DomainError } from "./accounts";
import { itemFor } from "./catalog";
import { database, transaction } from "./data";
export function bookmarksFor(actor: Account) {
  return database()
    .prepare("SELECT content FROM bookmarks WHERE user_id=? ORDER BY rowid")
    .all(actor.id)
    .flatMap((row) => {
      const bookmark = bookmarkSchema.parse(JSON.parse(z.string().parse(row.content)));
      try {
        itemFor(actor, bookmark.libraryItemId);
        return [bookmark];
      } catch (error) {
        if (error instanceof DomainError && error.status === 404) return [];
        throw error;
      }
    });
}

export const bookmarkInput = z.object({
  time: z.number().finite().min(0),
  title: z.string().trim().max(4096),
});
export const bookmarkTime = bookmarkInput.shape.time;
export function changeBookmark(
  actor: Account,
  itemId: string,
  input: z.infer<typeof bookmarkInput>,
  create: boolean,
) {
  return transaction((db) => {
    itemFor(actor, itemId);
    const matches = db
      .prepare("SELECT id,content FROM bookmarks WHERE user_id=? AND item_id=?")
      .all(actor.id, itemId);
    const existing = matches.find(
      (row) => bookmarkSchema.parse(JSON.parse(z.string().parse(row.content))).time === input.time,
    );
    if (!create && !existing) throw new DomainError(404, "Not found");
    if (
      !existing &&
      Number(db.prepare("SELECT count(*) AS count FROM bookmarks WHERE user_id=?").get(actor.id)?.count) >=
        100000
    )
      throw new DomainError(400, "Bookmark limit exceeded");
    const value = bookmarkSchema.parse({
      ...(existing ? JSON.parse(z.string().parse(existing.content)) : { createdAt: Date.now() }),
      libraryItemId: itemId,
      ...input,
    });
    if (existing)
      db.prepare("UPDATE bookmarks SET content=? WHERE id=? AND user_id=?").run(
        JSON.stringify(value),
        z.string().parse(existing.id),
        actor.id,
      );
    else
      db.prepare("INSERT INTO bookmarks VALUES(?,?,?,?)").run(
        randomUUID(),
        actor.id,
        itemId,
        JSON.stringify(value),
      );
    return value;
  });
}
export function deleteBookmark(actor: Account, itemId: string, time: number) {
  transaction((db) => {
    itemFor(actor, itemId);
    for (const row of db
      .prepare("SELECT id,content FROM bookmarks WHERE user_id=? AND item_id=?")
      .all(actor.id, itemId)) {
      if (bookmarkSchema.parse(JSON.parse(z.string().parse(row.content))).time === time)
        db.prepare("DELETE FROM bookmarks WHERE id=? AND user_id=?").run(z.string().parse(row.id), actor.id);
    }
  });
}
