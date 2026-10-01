import { beforeEach, describe, expect, it, vi } from "vitest";
import type { AbsClient } from "@/lib/abs/client";
import { usePlayerStore } from "@/lib/player/store";
import { discardProgress } from "./discard";
import { createListeningReport } from "./outbox";
import { flushReports, outboxFor } from "./sync";

function memoryStorage() {
  const data = new Map<string, string>();
  return {
    getItem: (key: string) => data.get(key) ?? null,
    setItem: (key: string, value: string) => void data.set(key, value),
    removeItem: (key: string) => void data.delete(key),
    key: (index: number) => [...data.keys()][index] ?? null,
    get length() {
      return data.size;
    },
    clear: () => data.clear(),
  };
}

const report = (id: string, itemId: string) =>
  createListeningReport(
    {
      id,
      libraryItemId: itemId,
      episodeId: null,
      libraryId: "lib1",
      mediaType: "book",
      displayTitle: itemId,
      displayAuthor: "QA",
      duration: 60,
      startTime: 0,
      startedAt: 1_000,
    },
    { currentTime: 40, timeListening: 40, localNow: 50_000, serverOffset: 0 },
  );

/** A server whose listening delivery answers only when the test says so, and which logs what reached it. */
function slowServer(connectionId: string) {
  const log: string[] = [];
  let deliver = () => {};
  const delivered = new Promise<void>((resolve) => {
    deliver = resolve;
  });
  const client = {
    connection: { id: connectionId, serverUrl: "https://abs.example", username: connectionId },
    send: vi.fn(async (_method: string, path: string, body: { sessions: { id: string }[] }) => {
      await delivered;
      log.push(`${path} ${body.sessions.map((session) => session.id).join(",")}`);
      return { results: body.sessions.map((session) => ({ id: session.id, success: true })) };
    }),
    command: vi.fn(async (method: string, path: string) => {
      log.push(`${method} ${path}`);
    }),
  } as unknown as AbsClient;
  return { client, log, deliver };
}

beforeEach(() => {
  vi.stubGlobal("localStorage", memoryStorage());
  usePlayerStore.setState({ player: { phase: "idle" }, client: null, connectionId: null, listening: null });
});

describe("discardProgress", () => {
  it("waits for listening already on its way to the server, so the old place cannot land after the discard", async () => {
    const server = slowServer("conn-a");
    usePlayerStore.getState().attach(server.client);
    outboxFor("conn-a").record(report("old-x", "book-x"));
    const delivering = flushReports(server.client, () => {});

    const discarding = discardProgress(server.client, {
      progressId: "p-x",
      itemId: "book-x",
      episodeId: null,
    });
    outboxFor("conn-a").record(report("new-z", "book-z"));
    await new Promise((resolve) => setTimeout(resolve, 10));
    server.deliver();
    await Promise.all([delivering, discarding]);

    expect(server.log).toEqual(["/api/session/local-all old-x", "DELETE /api/me/progress/p-x"]);
    expect(
      outboxFor("conn-a")
        .pending()
        .map((entry) => entry.id),
    ).toEqual(["new-z"]);
  });
});
