import { create } from "zustand";
import { type AbsClient, createAbsClient } from "@/lib/abs/client";
import type { Connection } from "@/lib/abs/connection";
import * as registry from "./registry";

export type Session =
  | { phase: "restoring" }
  | { phase: "signed-out" }
  | { phase: "signed-in"; connection: Connection; client: AbsClient; reauthRequired: boolean };

interface SessionStore {
  session: Session;
  restore: () => void;
  signIn: (connection: Connection) => void;
  signOut: () => void;
  switchTo: (id: string) => void;
  requireReauth: () => void;
}

function clientFor(connection: Connection) {
  return createAbsClient({
    connection,
    saveAuth: (auth) => registry.saveAuth(connection.id, auth),
    loadAuth: () => registry.loadAuth(connection.id),
  });
}

function sessionFrom(state: registry.Registry): Session {
  const connection = registry.activeConnection(state);
  return connection
    ? { phase: "signed-in", connection, client: clientFor(connection), reauthRequired: false }
    : { phase: "signed-out" };
}

export const useSessionStore = create<SessionStore>()((set, get) => ({
  session: { phase: "restoring" },
  restore: () => set({ session: sessionFrom(registry.loadRegistry()) }),
  signIn: (connection) => set({ session: sessionFrom(registry.saveSignedIn(connection)) }),
  signOut: () => {
    const { session } = get();
    if (session.phase === "signed-in") {
      const refresh = session.connection.auth.kind === "token" ? session.connection.auth.refreshToken : null;
      // Best effort: tell the server to end this session. Local sign-out must not depend on reaching it.
      if (refresh) {
        fetch(`${session.connection.serverUrl}/logout`, {
          method: "POST",
          headers: { "x-refresh-token": refresh },
          credentials: "omit",
        }).catch(() => {});
      }
      registry.signOut(session.connection.id);
    }
    set({ session: { phase: "signed-out" } });
  },
  switchTo: (id) => set({ session: sessionFrom(registry.switchTo(id)) }),
  requireReauth: () => {
    const { session } = get();
    if (session.phase === "signed-in" && !session.reauthRequired)
      set({ session: { ...session, reauthRequired: true } });
  },
}));

export function useSession() {
  return useSessionStore((state) => state.session);
}

/** For screens rendered only inside the signed-in shell. */
export function useAbs() {
  const session = useSession();
  if (session.phase !== "signed-in") throw new Error("useAbs outside a signed-in session");
  return session;
}
