import "server-only";
import { createHash } from "node:crypto";

// Exact 2.30 cache-maintenance definitions. Their SQL is archived, never installed or executed.
const derivedTriggers: Record<string, string> = {
  update_library_items_author_names_on_authors_update:
    "b4baa5f9bfa4c1eac863d0ed5681cec3a9dcec3e9f7dd4ecdc357886d4b66657",
  update_library_items_author_names_on_book_authors_delete:
    "de5d2deb1b24b7bfc205acf04b7713fd7239b6e64320a9871947231b33c3e578",
  update_library_items_author_names_on_book_authors_insert:
    "30d852a46bbb4fdd1bc67557dea6c1ee8878527d316d9cac238fa19d7d81a940",
  update_library_items_title: "b2a84c3adfc8640a7ffd951abb84cf9bddb1b8b5ee665e1631a0cada33177ca5",
  update_library_items_title_from_podcasts_title:
    "e3e9f1b8db800aae38e5b2b8c3ecb5c994a7949bbbf770662bebc91f448f6452",
  update_library_items_title_ignore_prefix:
    "85bb381ad2cc7e698d729162cb274961fcb9978f068e0b6d0a0b84ae33b24af8",
  update_library_items_title_ignore_prefix_from_podcasts_title_ignore_prefix:
    "583b8c7f2311daffa0800d225ab33b1fed98ac4569e602c000bee6e479808ea4",
};
export function knownDerivedTrigger(name: string, type: unknown, sql: unknown) {
  return (
    type === "trigger" &&
    typeof sql === "string" &&
    derivedTriggers[name] === createHash("sha256").update(sql).digest("hex")
  );
}
