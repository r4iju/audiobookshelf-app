import "server-only";
import { z } from "zod";
import { bookmarkSchema } from "@/lib/abs/schemas";
import { type Account, DomainError } from "./accounts";
import { itemFor } from "./catalog";
import { database } from "./data";
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
