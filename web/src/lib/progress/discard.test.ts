import { beforeEach, describe, expect, it, vi } from "vitest";
import type { AbsClient } from "@/lib/abs/client";
import { usePlayerStore } from "@/lib/player/store";
import { discardProgress } from "./discard";
import { createListeningReport, type ListeningReport } from "./outbox";
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

/**
 * A server that plays and records listening at once, but answers deletes only when the test says so. It logs, in
 * order, what it applied.
 */
function slowDeleteServer(connectionId: string) {
  const log: string[] = [];
  let deleteRequested = false;
  let finishDelete = () => {};
  const deleted = new Promise<void>((resolve) => {
    finishDelete = resolve;
  });
  const client = {
    connection: { id: connectionId, serverUrl: "https://abs.example", username: connectionId },
    url: (path: string) => `https://abs.example${path}`,
    send: vi.fn(async (_method: string, path: string, body: { sessions?: ListeningReport[] }) => {
      if (path.includes("/play")) {
        return {
          id: "s-new",
          libraryItemId: "book-x",
          episodeId: null,
          mediaType: "book",
          displayTitle: null,
          displayAuthor: null,
          duration: 60,
          currentTime: 0,
          playMethod: 0,
          chapters: [],
          audioTracks: [
            { index: 1, startOffset: 0, duration: 60, contentUrl: "/x.mp3", mimeType: "audio/mpeg" },
          ],
        };
      }
      const sessions = body.sessions ?? [];
      log.push(
        `listening ${sessions.map((session) => `${session.libraryItemId}@${session.currentTime}`).join(",")}`,
      );
      return { results: sessions.map((session) => ({ id: session.id, success: true })) };
    }),
    command: vi.fn(async (method: string, path: string) => {
      if (method !== "DELETE") return;
      deleteRequested = true;
      await deleted;
      log.push(`${method} ${path}`);
    }),
  } as unknown as AbsClient;
  return { client, log, finishDelete, deleteRequested: () => deleteRequested };
}

beforeEach(() => {
  vi.stubGlobal("localStorage", memoryStorage());
  vi.stubGlobal("document", { createElement: () => ({ canPlayType: () => "probably" }) });
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

  it("keeps listening begun after the reset, delivering it only once the discard is done", async () => {
    vi.useFakeTimers({ toFake: ["Date"] });
    const server = slowDeleteServer("conn-a");
    usePlayerStore.getState().attach(server.client);
    usePlayerStore.setState({
      player: {
        phase: "active",
        media: {
          itemId: "book-x",
          episodeId: null,
          libraryId: "lib1",
          mediaType: "book",
          title: "book-x",
          author: "QA",
          coverUrl: null,
          duration: 60,
          chapters: [],
        },
        source: { serverSessionId: "s-old", tracks: [], recovery: false },
        status: "playing",
        error: null,
        currentTime: 42,
        seekTo: { time: 42 },
      },
    });

    const discarding = discardProgress(server.client, {
      progressId: "p-x",
      itemId: "book-x",
      episodeId: null,
    });
    await vi.waitFor(() => expect(server.deleteRequested()).toBe(true));
    // Listening again from the start while the server is still deleting.
    const player = usePlayerStore.getState();
    await player.resume();
    player.onPlaying();
    vi.advanceTimersByTime(4_000);
    player.onTime(4);
    player.checkpoint();
    await flushReports(server.client, () => {});

    server.finishDelete();
    await discarding;
    await flushReports(server.client, () => {});
    vi.useRealTimers();

    expect(server.log).toEqual(["DELETE /api/me/progress/p-x", "listening book-x@4"]);
  });
});
