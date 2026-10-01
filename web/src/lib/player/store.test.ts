import { beforeEach, describe, expect, it, vi } from "vitest";
import type { AbsClient } from "@/lib/abs/client";
import { createListeningReport } from "@/lib/progress/outbox";
import { outboxFor } from "@/lib/progress/sync";
import { type PlayerMedia, usePlayerStore } from "./store";

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

/** A client whose session closes only when the test says so. */
function slowClient(connectionId: string) {
  let finishClose = () => {};
  const closing = new Promise<void>((resolve) => {
    finishClose = resolve;
  });
  const client = {
    connection: { id: connectionId, serverUrl: "https://abs.example", username: connectionId },
    command: vi.fn(() => closing),
  } as unknown as AbsClient;
  return { client, finishClose };
}

const media = (itemId: string): PlayerMedia => ({
  itemId,
  episodeId: null,
  libraryId: "lib1",
  mediaType: "book",
  title: itemId,
  author: "QA",
  coverUrl: null,
  duration: 60,
  chapters: [],
});

function playing(itemId: string, sessionId: string, currentTime: number) {
  return {
    phase: "active" as const,
    media: media(itemId),
    source: { serverSessionId: sessionId, tracks: [], recovery: false },
    status: "playing" as const,
    error: null,
    currentTime,
    seekTo: { time: currentTime },
  };
}

const report = (connectionSession: string, itemId: string) =>
  createListeningReport(
    {
      id: connectionSession,
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

beforeEach(() => {
  vi.stubGlobal("localStorage", memoryStorage());
  usePlayerStore.setState({ player: { phase: "idle" }, client: null, connectionId: null, listening: null });
});

describe("starting over after a discard", () => {
  it("leaves another book alone when that one started while the old session was closing", async () => {
    const a = slowClient("conn-a");
    usePlayerStore.getState().attach(a.client);
    usePlayerStore.setState({ player: playing("book-x", "s1", 42) });

    const discarding = usePlayerStore
      .getState()
      .startOver({ connectionId: "conn-a", itemId: "book-x", episodeId: null });
    usePlayerStore.setState({ player: playing("book-y", "s2", 7) });
    a.finishClose();
    await discarding;

    expect(usePlayerStore.getState().player).toEqual(playing("book-y", "s2", 7));
  });

  it("does not stop playback resumed after switching accounts away and back during the close", async () => {
    const a = slowClient("conn-a");
    usePlayerStore.getState().attach(a.client);
    usePlayerStore.setState({ player: playing("book-x", "s1", 42) });
    localStorage.setItem(
      "abs-web:v1:player:conn-a",
      JSON.stringify({ media: media("book-x"), currentTime: 42 }),
    );

    const discarding = usePlayerStore
      .getState()
      .startOver({ connectionId: "conn-a", itemId: "book-x", episodeId: null });
    usePlayerStore.getState().detach();
    usePlayerStore.getState().attach(slowClient("conn-b").client);
    usePlayerStore.getState().detach();
    usePlayerStore.getState().attach(slowClient("conn-a").client);
    // Back on the first account, the book comes back where the discard left it, not at the old place.
    const restored = usePlayerStore.getState().player;
    expect(restored.phase === "active" ? restored.currentTime : null).toBe(0);
    usePlayerStore.setState({ player: playing("book-x", "s3", 3) });
    a.finishClose();
    await discarding;

    expect(usePlayerStore.getState().player).toEqual(playing("book-x", "s3", 3));
  });

  it("forgets unsent listening of the account the discard came from, not of the one signed in now", async () => {
    outboxFor("conn-a").record(report("a1", "book-x"));
    outboxFor("conn-b").record(report("b1", "book-x"));
    usePlayerStore.getState().attach(slowClient("conn-b").client);

    await usePlayerStore.getState().startOver({ connectionId: "conn-a", itemId: "book-x", episodeId: null });

    expect(outboxFor("conn-a").pending()).toEqual([]);
    expect(
      outboxFor("conn-b")
        .pending()
        .map((entry) => entry.id),
    ).toEqual(["b1"]);
  });

  it("records nothing more for the book while its old session is still closing", async () => {
    const a = slowClient("conn-a");
    usePlayerStore.getState().attach(a.client);
    usePlayerStore.setState({
      player: playing("book-x", "s1", 42),
      listening: {
        identity: { ...report("s1", "book-x"), startTime: 0 },
        timeListening: 30,
        serverOffset: 0,
        lastTick: null,
        lastReportedAt: 0,
        last: null,
      },
    });

    const discarding = usePlayerStore
      .getState()
      .startOver({ connectionId: "conn-a", itemId: "book-x", episodeId: null });
    usePlayerStore.getState().onTime(43);
    usePlayerStore.getState().checkpoint();
    a.finishClose();
    await discarding;

    expect(outboxFor("conn-a").pending()).toEqual([]);
    const player = usePlayerStore.getState().player;
    expect(player.phase === "active" ? player.currentTime : null).toBe(0);
  });
});
