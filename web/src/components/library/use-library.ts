import { useEffect } from "react";
import { coverShapeOf } from "@/lib/abs/media";
import { useLibraries } from "@/lib/abs/queries";
import * as registry from "@/lib/session/registry";
import { useAbs } from "@/lib/session/store";

/** The library named in the URL, remembered as this connection's last library. */
export function useLibrary(libraryId: string) {
  const { connection } = useAbs();
  const libraries = useLibraries();
  const library = libraries.data?.find((entry) => entry.id === libraryId);

  // External system: the last opened library is persisted in this browser for the next visit.
  useEffect(() => {
    if (library) registry.rememberLibrary(connection.id, library.id);
  }, [connection.id, library]);

  return { library, shape: coverShapeOf(library), libraries };
}
