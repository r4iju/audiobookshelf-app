import { useEffect } from "react";
import { coverShapeOf } from "@/lib/abs/media";
import { useLibraries } from "@/lib/abs/queries";
import { useCurrentLibrary } from "@/lib/session/current-library";
import * as registry from "@/lib/session/registry";
import { useAbs } from "@/lib/session/store";

/** The library the page belongs to, remembered as this connection's last library and shown as current. */
export function useLibrary(libraryId: string | undefined) {
  const { connection } = useAbs();
  const libraries = useLibraries();
  const library = libraries.data?.find((entry) => entry.id === libraryId);
  const show = useCurrentLibrary((state) => state.show);

  // External system: the last opened library is persisted in this browser for the next visit.
  useEffect(() => {
    if (!library) return;
    registry.rememberLibrary(connection.id, library.id);
    show(library.id);
  }, [connection.id, library, show]);

  return { library, shape: coverShapeOf(library), libraries };
}
