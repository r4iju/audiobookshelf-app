import { afterEach, expect, it, vi } from "vitest";
import { createAbsClient } from "@/lib/abs/client";
import type { Connection } from "@/lib/abs/connection";
import * as registry from "./registry";
import { useSessionStore } from "./store";

vi.mock("./registry", () => ({
  loadRegistry: vi.fn(),
  activeConnection: vi.fn(),
  saveSignedIn: vi.fn(),
  saveAuth: vi.fn(),
  loadAuth: vi.fn(),
  signOut: vi.fn(),
}));
afterEach(() => {
  vi.restoreAllMocks();
  vi.unstubAllGlobals();
});
it("browser sign-out revokes the current rotated session and clears local credentials", () => {
  const connection: Connection = {
    id: "test-connection",
    serverUrl: "https://library.example",
    userId: "user",
    username: "user",
    auth: { kind: "token", accessToken: "original-access", refreshToken: "original-refresh" },
  };
  vi.mocked(registry.loadAuth).mockReturnValue({
    kind: "token",
    accessToken: "rotated-access",
    refreshToken: "rotated-refresh",
  });
  const fetcher = vi.fn().mockResolvedValue(new Response());
  vi.stubGlobal("fetch", fetcher);
  useSessionStore.setState({
    session: {
      phase: "signed-in",
      connection,
      client: createAbsClient({ connection, saveAuth: () => {} }),
      reauthRequired: false,
    },
  });
  useSessionStore.getState().signOut();
  expect(fetcher).toHaveBeenCalledWith(
    "https://library.example/logout",
    expect.objectContaining({ headers: { "x-refresh-token": "rotated-refresh" } }),
  );
  expect(registry.signOut).toHaveBeenCalledWith(connection.id);
  expect(useSessionStore.getState().session.phase).toBe("signed-out");
});
