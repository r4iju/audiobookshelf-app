import { z } from "zod";
import type { AuthState, Connection, SavedConnection } from "@/lib/abs/connection";
import { savedConnectionSchema } from "@/lib/abs/connection";
import { readStored, writeStored } from "@/lib/storage/local";

// Saved servers live in this browser only. Keyed per connection so a rejected sign-in on one server never touches
// another server's credentials or queued progress.
const KEY = "abs-web:v1:connections";

const registrySchema = z.object({
  activeId: z.string().nullable(),
  connections: z.array(savedConnectionSchema),
});
export type Registry = z.infer<typeof registrySchema>;

export function loadRegistry(): Registry {
  return readStored(KEY, registrySchema) ?? { activeId: null, connections: [] };
}

function update(change: (registry: Registry) => Registry) {
  const next = change(loadRegistry());
  writeStored(KEY, next);
  return next;
}

export function activeConnection(registry: Registry): Connection | null {
  const saved = registry.connections.find((entry) => entry.id === registry.activeId);
  return saved?.auth ? { ...saved, auth: saved.auth } : null;
}

export function saveSignedIn(connection: Connection) {
  return update((registry) => ({
    activeId: connection.id,
    connections: [
      ...registry.connections.filter((entry) => entry.id !== connection.id),
      {
        ...connection,
        lastLibraryId: registry.connections.find((entry) => entry.id === connection.id)?.lastLibraryId,
      },
    ],
  }));
}

export function saveAuth(id: string, auth: AuthState) {
  return update((registry) => ({
    ...registry,
    connections: registry.connections.map((entry) => (entry.id === id ? { ...entry, auth } : entry)),
  }));
}

export function loadAuth(id: string): AuthState | null {
  return loadRegistry().connections.find((entry) => entry.id === id)?.auth ?? null;
}

/** Forgets credentials but keeps the server entry (and anything queued for it) for a later sign-in. */
export function signOut(id: string) {
  return update((registry) => ({
    activeId: registry.activeId === id ? null : registry.activeId,
    connections: registry.connections.map((entry) => (entry.id === id ? { ...entry, auth: null } : entry)),
  }));
}

export function switchTo(id: string) {
  return update((registry) => ({ ...registry, activeId: id }));
}

export function forget(id: string) {
  return update((registry) => ({
    activeId: registry.activeId === id ? null : registry.activeId,
    connections: registry.connections.filter((entry) => entry.id !== id),
  }));
}

export function rememberLibrary(id: string, libraryId: string) {
  if (loadRegistry().connections.find((entry) => entry.id === id)?.lastLibraryId === libraryId) return;
  update((registry) => ({
    ...registry,
    connections: registry.connections.map((entry) =>
      entry.id === id ? { ...entry, lastLibraryId: libraryId } : entry,
    ),
  }));
}

export function lastLibraryId(id: string) {
  return loadRegistry().connections.find((entry) => entry.id === id)?.lastLibraryId ?? null;
}

export type { SavedConnection };
