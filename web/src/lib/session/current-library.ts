import { create } from "zustand";

/** The library the open page belongs to, for pages whose address does not name it (items, collections, playlists). */
export const useCurrentLibrary = create<{ libraryId: string | null; show: (libraryId: string) => void }>()(
  (set) => ({ libraryId: null, show: (libraryId) => set({ libraryId }) }),
);
