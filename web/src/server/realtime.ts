import { serverSettings } from "./server-settings";
import "server-only";
import type { LibraryItem, User } from "@/lib/abs/schemas";
import { accountResponse, authenticate } from "./accounts";
import { itemFor, itemsFor, librariesFor } from "./catalog";
import { realtimeLists } from "./lists";

type Snapshot = {
  user: User;
  items: LibraryItem[];
  lists: ReturnType<typeof realtimeLists>;
  serverSettings: { version: string; language: string };
};
type Change =
  | { userId: string; itemId?: string }
  | { catalog: true }
  | { lists: true }
  | { podcast: { name: string; itemId: string; data: unknown } };
declare global {
  var leafwakeRealtimeSnapshot: ((token: string) => Snapshot) | undefined;
  var leafwakeRealtimeCheck: ((token: string) => void) | undefined;
  var leafwakeRealtimeItem: ((token: string, id: string) => LibraryItem) | undefined;
  var leafwakeRealtimeChanged: ((change?: Change) => void) | undefined;
  var leafwakeCatalogRevision: number | undefined;
  var leafwakeBasePath: string | undefined;
}
const catalogs = new Map<string, { revision: number; items: LibraryItem[] }>();
// The custom HTTP entry and Next route bundles share this process, never another backend.
globalThis.leafwakeRealtimeCheck = (token) => {
  authenticate(token);
};
globalThis.leafwakeRealtimeItem = (token, id) => itemFor(authenticate(token), id);
globalThis.leafwakeRealtimeSnapshot = (token) => {
  const actor = authenticate(token);
  const key = JSON.stringify([actor.permissions, actor.libraries, actor.tags]);
  const revision = globalThis.leafwakeCatalogRevision ?? 0;
  let catalog = catalogs.get(key);
  if (!catalog || catalog.revision !== revision) {
    catalog = {
      revision,
      items: librariesFor(actor).flatMap((library) => itemsFor(actor, library.id, false)),
    };
    if (catalogs.size >= 256) catalogs.clear();
    catalogs.set(key, catalog);
  }
  return {
    user: accountResponse(actor),
    items: catalog.items,
    lists: realtimeLists(actor, catalog.items),
    serverSettings: { version: "1.0.0-dev", language: serverSettings().language },
  };
};
