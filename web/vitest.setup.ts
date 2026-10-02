import "fake-indexeddb/auto";
import { IDBFactory } from "fake-indexeddb";
import { beforeEach, vi } from "vitest";

// Each test starts with empty IndexedDB, as a fresh browser profile would.
beforeEach(() => {
  vi.stubGlobal("indexedDB", new IDBFactory());
});
