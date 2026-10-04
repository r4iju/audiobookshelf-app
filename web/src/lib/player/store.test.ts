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

/** A client whose playback opens only when the test says so, and which logs the sessions it is asked to close. */
function slowOpenClient(connectionId: string) {
  const closed: string[] = [];
  let open = (_session: { id: string; currentTime: number }) => {};
  const opening = new Promise<{ id: string; currentTime: number }>((resolve) => {
    open = resolve;
  });
  const client = {
    connection: { id: connectionId, serverUrl: "https://abs.example", username: connectionId },
    url: (path: string) => `https://abs.example${path}`,
    send: vi.fn(async (_method: string, path: string) => {
      const { id, currentTime } = await opening;
      return {
        id,
        libraryItemId: path.split("/")[3],
        episodeId: null,
        mediaType: "book",
        displayTitle: null,
        displayAuthor: null,
        duration: 60,
        currentTime,
        playMethod: 0,
        chapters: [],
        audioTracks: [
          { index: 1, startOffset: 0, duration: 60, contentUrl: "/x.mp3", mimeType: "audio/mpeg" },
        ],
      };
    }),
    command: vi.fn(async (_method: string, path: string) => {
      closed.push(path);
    }),
  } as unknown as AbsClient;
  return { client, open, closed };
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
  vi.stubGlobal("document", { createElement: () => ({ canPlayType: () => "probably" }) });
  usePlayerStore.setState({ player: { phase: "idle" }, client: null, connectionId: null, listening: null });
});

describe("starting over after a discard", () => {
  it("allows a later media renewal after recovered audio actually plays", async () => {
    const current = playing("book-x", "renewed-session", 42);
    usePlayerStore.setState({ player: { ...current, source: { ...current.source, recovery: true } } });
    usePlayerStore.getState().onPlaying();
    const state = usePlayerStore.getState().player;
    expect(state.phase === "active" && state.source?.recovery).toBe(false);
  });
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

  it("keeps the reset when the book was still being prepared and its session opens afterwards", async () => {
    const a = slowOpenClient("conn-a");
    usePlayerStore.getState().attach(a.client);

    const preparing = usePlayerStore.getState().play({ media: media("book-x") });
    await usePlayerStore.getState().startOver({ connectionId: "conn-a", itemId: "book-x", episodeId: null });
    a.open({ id: "s-old", currentTime: 42 });
    await preparing;

    const player = usePlayerStore.getState().player;
    expect(
      player.phase === "active" && { time: player.currentTime, source: player.source, status: player.status },
    ).toEqual({
      time: 0,
      source: null,
      status: "paused",
    });
    expect(usePlayerStore.getState().listening).toBeNull();
    expect(a.closed).toEqual(["/api/session/s-old/close"]);
  });

  it("does not start a book prepared before switching accounts away and back", async () => {
    const a = slowOpenClient("conn-a");
    usePlayerStore.getState().attach(a.client);
    localStorage.setItem(
      "abs-web:v1:player:conn-a",
      JSON.stringify({ media: media("book-x"), currentTime: 5 }),
    );

    const preparing = usePlayerStore.getState().play({ media: media("book-x") });
    usePlayerStore.getState().detach();
    usePlayerStore.getState().attach(slowOpenClient("conn-b").client);
    usePlayerStore.getState().detach();
    usePlayerStore.getState().attach(slowOpenClient("conn-a").client);
    a.open({ id: "s-old", currentTime: 42 });
    await preparing;

    const player = usePlayerStore.getState().player;
    expect(
      player.phase === "active" && { time: player.currentTime, source: player.source, status: player.status },
    ).toEqual({
      time: 5,
      source: null,
      status: "paused",
    });
    expect(a.closed).toEqual(["/api/session/s-old/close"]);
  });
});

describe("the sleep timer at the end of a chapter", () => {
  it("stops where the chapter ends with its file, though no time was reported at the very end", () => {
    const chapters = [
      { id: 0, start: 0, end: 30, title: "Arrival" },
      { id: 1, start: 30, end: 60, title: "Crossing" },
    ];
    const tracks = [
      { url: "/1.mp3", startOffset: 0, duration: 30, hls: false },
      { url: "/2.mp3", startOffset: 30, duration: 30, hls: false },
    ];
    const at = playing("book-x", "s-1", 29.6);
    usePlayerStore.setState({
      player: { ...at, media: { ...at.media, chapters }, source: { ...at.source, tracks } },
      sleep: { kind: "chapter-end", at: 30 },
    });

    usePlayerStore.getState().onFileEnded(30);

    const { player, sleep } = usePlayerStore.getState();
    expect({ status: player.phase === "active" && player.status, sleep }).toEqual({
      status: "paused",
      sleep: { kind: "off" },
    });
  });
});
