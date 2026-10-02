import { MutationObserver, QueryClient } from "@tanstack/react-query";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { type AbsClient, AbsError, createAbsClient } from "@/lib/abs/client";
import { ebookPlaceSaves } from "@/lib/abs/mutations";
import { localSyncResultSchema } from "@/lib/abs/schemas";
import { usePlayerStore } from "@/lib/player/store";
import { beginPublishing, finishSending, reattempt } from "./coordination";
import { discardProgress } from "./discard";
import { createListeningReport, createOutbox, type ListeningReport } from "./outbox";
import {
  changeProgress,
  confirmServerRestarted,
  discardAnyway,
  finishDiscard,
  flushReports,
  heldDeliveries,
  issueChange,
  keepProgress,
  outboxFor,
  requestServerRestart,
} from "./sync";

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

const report = (id: string, itemId: string, { currentTime = 40, localNow = 50_000 } = {}) =>
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
    { currentTime, timeListening: currentTime, localNow, serverOffset: 0 },
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

/** What the server answers to a play request, starting from the place it has saved. */
const playSession = (id: string, currentTime: number) => ({
  id,
  libraryItemId: "book-x",
  episodeId: null,
  mediaType: "book",
  displayTitle: null,
  displayAuthor: null,
  duration: 60,
  currentTime,
  playMethod: 0,
  chapters: [],
  audioTracks: [{ index: 1, startOffset: 0, duration: 60, contentUrl: "/x.mp3", mimeType: "audio/mpeg" }],
});

/**
 * A server whose answers to deletes are scripted in order: "hang" never answers until thawed (a frozen tab's
 * request), "refuse" fails as an unreachable server would, "ok" deletes. It logs, in order, what it applied.
 */
function scriptedDeleteServer(connectionId: string, script: ("hang" | "refuse" | "ok")[]) {
  const log: string[] = [];
  let thaw = () => {};
  const thawed = new Promise<void>((resolve) => {
    thaw = resolve;
  });
  let deletes = 0;
  const client = {
    connection: { id: connectionId, serverUrl: "https://abs.example", username: connectionId },
    url: (path: string) => `https://abs.example${path}`,
    send: vi.fn(async (_method: string, path: string, body: { sessions: ListeningReport[] }) => {
      if (path.includes("/play")) return playSession("s-new", 42);
      log.push(
        `listening ${body.sessions.map((session) => `${session.libraryItemId}@${session.currentTime}`).join(",")}`,
      );
      return { results: body.sessions.map((session) => ({ id: session.id, success: true })) };
    }),
    command: vi.fn(async (method: string, path: string) => {
      if (method === "PATCH") log.push(`${method} ${path}`);
      if (method !== "DELETE") return;
      const answer = script[deletes++] ?? "ok";
      if (answer === "refuse") throw new AbsError("network", "Network error");
      if (answer === "hang") await thawed;
      log.push(`${method} ${path}`);
    }),
  } as unknown as AbsClient;
  return { client, log, thaw, deletes: () => deletes };
}

/** The same browser storage as seen from another tab of this origin. */
const sharedStorage = {
  read: (key: string) => localStorage.getItem(key),
  write: (key: string, value: string) => localStorage.setItem(key, value),
  remove: (key: string) => localStorage.removeItem(key),
  keys: (prefix: string) =>
    Array.from({ length: localStorage.length }, (_, index) => localStorage.key(index) ?? "").filter((key) =>
      key.startsWith(prefix),
    ),
};

/** Another tab's view of the storage that has not yet received this tab's holds, as browsers pass writes on later. */
const laggingStorage = {
  ...sharedStorage,
  read: (key: string) => (key.includes("outbox-hold") ? null : sharedStorage.read(key)),
  keys: (prefix: string) => sharedStorage.keys(prefix).filter((key) => !key.includes("outbox-hold")),
};

/**
 * Another tab of the same account, whose delivery the server answers only when the test says so. `fails` makes the
 * request fail instead, `storage` is its view of the browser's storage, and `registering` delays the tab between choosing what to send and recording it.
 */
function otherTab(
  log: string[],
  { page = "page-other", fails = false, registering = Promise.resolve(), storage = sharedStorage } = {},
) {
  const outbox = createOutbox("conn-a", storage, undefined, {
    begin: async (connectionId, candidates) => {
      await registering;
      return beginPublishing(connectionId, candidates, page);
    },
    finish: finishSending,
    reattempt,
  });
  let answer = () => {};
  const answered = new Promise<void>((resolve) => {
    answer = resolve;
  });
  let sent = false;
  const delivering = () =>
    outbox.flush(async (sessions) => {
      sent = true;
      await answered;
      if (fails) throw new AbsError("network", "Network error");
      log.push(
        `listening ${sessions.map((session) => `${session.libraryItemId}@${session.currentTime}`).join(",")}`,
      );
      return sessions.map((session) => ({ id: session.id, success: true }));
    });
  return { delivering, answer, sent: () => sent };
}

/** What this origin's coordination database holds under `prefix`. */
async function coordinationRecords(prefix: string) {
  const db = await new Promise<IDBDatabase>((resolve, reject) => {
    const request = indexedDB.open("abs-web-coordination", 1);
    request.onsuccess = () => resolve(request.result);
    request.onerror = () => reject(request.error);
  });
  const records = await new Promise<{ key: string }[]>((resolve, reject) => {
    const all = db.transaction("entries").objectStore("entries").getAll();
    all.onsuccess = () => resolve(all.result);
    all.onerror = () => reject(all.error);
  });
  db.close();
  return records.filter((record) => record.key.startsWith(prefix));
}

/** Writes records into this origin's coordination database as an earlier version of the client left them. */
async function storedCoordination(records: object[]) {
  const db = await new Promise<IDBDatabase>((resolve, reject) => {
    const request = indexedDB.open("abs-web-coordination", 1);
    request.onupgradeneeded = () => request.result.createObjectStore("entries", { keyPath: "key" });
    request.onsuccess = () => resolve(request.result);
    request.onerror = () => reject(request.error);
  });
  await new Promise<void>((resolve, reject) => {
    const transaction = db.transaction("entries", "readwrite");
    for (const record of records) transaction.objectStore("entries").put(record);
    transaction.oncomplete = () => resolve();
    transaction.onabort = () => reject(transaction.error);
  });
  db.close();
}

beforeEach(() => {
  vi.stubGlobal("localStorage", memoryStorage());
  vi.stubGlobal("document", { createElement: () => ({ canPlayType: () => "probably" }) });
  usePlayerStore.setState({ player: { phase: "idle" }, client: null, connectionId: null, listening: null });
});

afterEach(() => {
  vi.useRealTimers();
});

describe("discardProgress", () => {
  it("waits for listening already on its way to the server, so the old place cannot land after the discard", async () => {
    const server = slowServer("conn-a");
    usePlayerStore.getState().attach(server.client);
    outboxFor("conn-a").record(report("old-x", "book-x"));
    const delivering = flushReports(server.client, () => {});
    await vi.waitFor(() => expect(server.client.send).toHaveBeenCalled());

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

  it("does not delete progress the user chose to keep while this tab's own listening was on its way", async () => {
    const server = slowServer("conn-a");
    usePlayerStore.getState().attach(server.client);
    outboxFor("conn-a").record(report("old-x", "book-x"));
    const delivering = flushReports(server.client, () => {});
    await vi.waitFor(() => expect(server.client.send).toHaveBeenCalled());

    const discarding = discardProgress(server.client, {
      progressId: "p-x",
      itemId: "book-x",
      episodeId: null,
    });
    await vi.waitFor(() => expect(outboxFor("conn-a").discardState("book-x", null)).toBe("pending"));
    await keepProgress(server.client, "book-x", null);
    server.deliver();
    await Promise.all([delivering, discarding]);

    expect(server.log).toEqual(["/api/session/local-all old-x"]);
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

  it("keeps holding new listening however long the delete takes", async () => {
    vi.useFakeTimers({ toFake: ["Date"] });
    const server = slowDeleteServer("conn-a");
    usePlayerStore.getState().attach(server.client);

    const discarding = discardProgress(server.client, {
      progressId: "p-x",
      itemId: "book-x",
      episodeId: null,
    });
    await vi.waitFor(() => expect(server.deleteRequested()).toBe(true));
    outboxFor("conn-a").record({ ...report("new-x", "book-x"), currentTime: 4 });
    vi.advanceTimersByTime(60 * 60_000);
    await flushReports(server.client, () => {});

    server.finishDelete();
    await discarding;
    await flushReports(server.client, () => {});
    vi.useRealTimers();

    expect(server.log).toEqual(["DELETE /api/me/progress/p-x", "listening book-x@4"]);
  });

  it("finishes a discard whose tab stopped answering before delivering the listening it held", async () => {
    vi.stubGlobal("navigator", { userAgent: "Chrome/1", platform: "test" });
    vi.useFakeTimers({ toFake: ["Date"] });
    const server = scriptedDeleteServer("conn-a", ["hang"]);
    usePlayerStore.getState().attach(server.client);

    const discarding = discardProgress(server.client, {
      progressId: "p-x",
      itemId: "book-x",
      episodeId: null,
    });
    await vi.waitFor(() => expect(server.deletes()).toBe(1));
    outboxFor("conn-a").record({ ...report("new-x", "book-x"), currentTime: 4 });
    // The discarding tab is frozen: without Web Locks, nothing tells the others it is still there.
    vi.advanceTimersByTime(60 * 60_000);
    await flushReports(server.client, () => {});
    // It wakes, and its request reaches the server late.
    server.thaw();
    await discarding;

    expect(server.log).toEqual([
      "DELETE /api/me/progress/p-x",
      "listening book-x@4",
      "DELETE /api/me/progress/p-x",
    ]);
  });

  it("keeps a refused discard and its new listening, and finishes it once the server answers", async () => {
    const server = scriptedDeleteServer("conn-a", ["refuse"]);
    usePlayerStore.getState().attach(server.client);

    await expect(
      discardProgress(server.client, { progressId: "p-x", itemId: "book-x", episodeId: null }),
    ).rejects.toThrow();
    outboxFor("conn-a").record({ ...report("new-x", "book-x"), currentTime: 4 });
    await flushReports(server.client, () => {});

    expect(server.log).toEqual(["DELETE /api/me/progress/p-x", "listening book-x@4"]);
  });

  it("plays a book whose discard is still pending from the start, not from the server's old place", async () => {
    const server = scriptedDeleteServer("conn-a", ["refuse"]);
    usePlayerStore.getState().attach(server.client);
    await expect(
      discardProgress(server.client, { progressId: "p-x", itemId: "book-x", episodeId: null }),
    ).rejects.toThrow();

    await usePlayerStore.getState().play({
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
    });

    const player = usePlayerStore.getState().player;
    expect(player.phase === "active" ? player.currentTime : null).toBe(0);
  });

  it("leaves a discard unconfirmed while another tab's listening is on its way, and finishes it once answered, without Web Locks", async () => {
    vi.stubGlobal("navigator", { userAgent: "Chrome/1", platform: "test" });
    const server = scriptedDeleteServer("conn-a", ["ok"]);
    usePlayerStore.getState().attach(server.client);
    outboxFor("conn-a").record(report("old-x", "book-x"));
    const tab = otherTab(server.log);
    const delivering = tab.delivering();
    await vi.waitFor(() => expect(tab.sent()).toBe(true));

    const result = await discardProgress(server.client, {
      progressId: "p-x",
      itemId: "book-x",
      episodeId: null,
    });
    expect(result).toBe("unconfirmed");
    expect(outboxFor("conn-a").discardState("book-x", null)).toBe("unconfirmed");
    tab.answer();
    await delivering;
    await flushReports(server.client, () => {});

    expect(server.log).toEqual(["listening book-x@40", "DELETE /api/me/progress/p-x"]);
    expect(outboxFor("conn-a").discardState("book-x", null)).toBeNull();
  });

  it("does not send another tab's listening for a book blocked after it chose what to send, without Web Locks", async () => {
    vi.stubGlobal("navigator", { userAgent: "Chrome/1", platform: "test" });
    const server = scriptedDeleteServer("conn-a", ["ok"]);
    usePlayerStore.getState().attach(server.client);
    outboxFor("conn-a").record(report("old-x", "book-x"));
    let register = () => {};
    const registering = new Promise<void>((resolve) => {
      register = resolve;
    });
    const tab = otherTab(server.log, { registering });
    const delivering = tab.delivering();

    await discardProgress(server.client, { progressId: "p-x", itemId: "book-x", episodeId: null });
    register();
    tab.answer();
    await delivering;

    expect(server.log).toEqual(["DELETE /api/me/progress/p-x"]);
  });

  it("keeps a discard unconfirmed, sending nothing, when another tab's delivery failed without an answer", async () => {
    vi.stubGlobal("navigator", { userAgent: "Chrome/1", platform: "test" });
    const server = scriptedDeleteServer("conn-a", ["ok"]);
    usePlayerStore.getState().attach(server.client);
    outboxFor("conn-a").record(report("old-x", "book-x"));
    const tab = otherTab(server.log, { fails: true });
    const delivering = tab.delivering();
    await vi.waitFor(() => expect(tab.sent()).toBe(true));

    await discardProgress(server.client, { progressId: "p-x", itemId: "book-x", episodeId: null });
    tab.answer();
    await delivering;
    await flushReports(server.client, () => {});

    // The failed request may still reach the server, or be running there; nothing shows when it is done.
    expect(server.log).toEqual([]);
    expect(outboxFor("conn-a").discardState("book-x", null)).toBe("unconfirmed");
  });

  it("keeps the progress when told to, deleting nothing even for a tab that wakes later, and delivers what was held", async () => {
    vi.stubGlobal("navigator", { userAgent: "Chrome/1", platform: "test" });
    const server = scriptedDeleteServer("conn-a", ["ok"]);
    usePlayerStore.getState().attach(server.client);
    outboxFor("conn-a").record(report("old-x", "book-x"));
    const tab = otherTab(server.log, { fails: true });
    const delivering = tab.delivering();
    await vi.waitFor(() => expect(tab.sent()).toBe(true));
    await discardProgress(server.client, { progressId: "p-x", itemId: "book-x", episodeId: null });
    tab.answer();
    await delivering;
    const [hold] = outboxFor("conn-a").holdsFor("book-x", null);
    if (!hold) throw new Error("The discard left no hold");
    outboxFor("conn-a").record(report("new-x", "book-x"));

    await keepProgress(server.client, "book-x", null);
    await finishDiscard(server.client, hold, {});
    await flushReports(server.client, () => {});

    // The failed request's version, sent again unchanged, and the held listening.
    expect(server.log).toEqual(["listening book-x@40,book-x@40"]);
    expect(outboxFor("conn-a").discardState("book-x", null)).toBeNull();
  });

  it("discards anyway when told to, though another tab's delivery is unconfirmed", async () => {
    vi.stubGlobal("navigator", { userAgent: "Chrome/1", platform: "test" });
    const server = scriptedDeleteServer("conn-a", ["ok"]);
    usePlayerStore.getState().attach(server.client);
    outboxFor("conn-a").record(report("old-x", "book-x"));
    const tab = otherTab(server.log, { fails: true });
    const delivering = tab.delivering();
    await vi.waitFor(() => expect(tab.sent()).toBe(true));
    await discardProgress(server.client, { progressId: "p-x", itemId: "book-x", episodeId: null });
    tab.answer();
    await delivering;

    await discardAnyway(server.client, "book-x", null);

    expect(server.log).toEqual(["DELETE /api/me/progress/p-x"]);
    expect(outboxFor("conn-a").discardState("book-x", null)).toBeNull();
  });

  it("does not delete again, or block the book again, for a tab that wakes after its discard was finished", async () => {
    vi.stubGlobal("navigator", { userAgent: "Chrome/1", platform: "test" });
    const server = scriptedDeleteServer("conn-a", ["ok", "ok"]);
    usePlayerStore.getState().attach(server.client);
    await discardProgress(server.client, { progressId: "p-x", itemId: "book-x", episodeId: null });
    const late = { id: "late", libraryItemId: "book-x", episodeId: null, progressId: "p-x" };
    await finishDiscard(server.client, late, {});

    await finishDiscard(server.client, late, {});
    outboxFor("conn-a").record(report("new-x", "book-x"));
    await flushReports(server.client, () => {});

    expect(server.log).toEqual([
      "DELETE /api/me/progress/p-x",
      "DELETE /api/me/progress/p-x",
      "listening book-x@40",
    ]);
  });

  it("keeps another tab from sending new listening during the delete before that tab sees the hold", async () => {
    vi.stubGlobal("navigator", { userAgent: "Chrome/1", platform: "test" });
    const server = scriptedDeleteServer("conn-a", ["hang"]);
    usePlayerStore.getState().attach(server.client);
    const discarding = discardProgress(server.client, {
      progressId: "p-x",
      itemId: "book-x",
      episodeId: null,
    });
    await vi.waitFor(() => expect(server.deletes()).toBe(1));
    outboxFor("conn-a").record(report("new-x", "book-x"));

    const tab = otherTab(server.log, { storage: laggingStorage });
    tab.answer();
    await tab.delivering();
    server.thaw();
    await discarding;

    expect(server.log).toEqual(["DELETE /api/me/progress/p-x"]);
  });

  it("waits for another tab's request, sending no copy of it meanwhile", async () => {
    vi.stubGlobal("navigator", { userAgent: "Chrome/1", platform: "test" });
    const server = scriptedDeleteServer("conn-a", ["ok"]);
    usePlayerStore.getState().attach(server.client);
    outboxFor("conn-a").record(report("old-x", "book-x"));
    const tab = otherTab(server.log);
    const delivering = tab.delivering();
    await vi.waitFor(() => expect(tab.sent()).toBe(true));
    await flushReports(server.client, () => {});

    const result = await discardProgress(server.client, {
      progressId: "p-x",
      itemId: "book-x",
      episodeId: null,
    });
    expect({ result, log: [...server.log] }).toEqual({ result: "unconfirmed", log: [] });
    tab.answer();
    await delivering;
    await flushReports(server.client, () => {});

    expect(server.log).toEqual(["listening book-x@40", "DELETE /api/me/progress/p-x"]);
  });

  it("lets no tab keep the progress once its delete is on its way, holding new listening until the delete is answered", async () => {
    vi.stubGlobal("navigator", { userAgent: "Chrome/1", platform: "test" });
    const server = scriptedDeleteServer("conn-a", ["hang"]);
    usePlayerStore.getState().attach(server.client);
    const discarding = discardProgress(server.client, {
      progressId: "p-x",
      itemId: "book-x",
      episodeId: null,
    });
    await vi.waitFor(() => expect(server.deletes()).toBe(1));
    outboxFor("conn-a").record(report("new-x", "book-x"));

    // Another tab still offering Keep, or recovering the discard on its own, chooses to keep.
    await keepProgress(server.client, "book-x", null);
    await flushReports(server.client, () => {});
    expect({ log: [...server.log], state: outboxFor("conn-a").discardState("book-x", null) }).toEqual({
      log: [],
      state: "pending",
    });
    server.thaw();
    await discarding;
    await flushReports(server.client, () => {});

    expect(server.log).toEqual(["DELETE /api/me/progress/p-x", "listening book-x@40"]);
  });

  it("leaves a discard unconfirmed, deleting nothing, when a reading place for the book failed without an answer", async () => {
    vi.stubGlobal("navigator", { userAgent: "Chrome/1", platform: "test" });
    const server = scriptedDeleteServer("conn-a", ["ok"]);
    usePlayerStore.getState().attach(server.client);
    const reader = {
      ...server.client,
      command: vi.fn(async () => {
        throw new AbsError("network", "Network error");
      }),
    } as unknown as AbsClient;
    await expect(
      changeProgress(
        reader,
        { libraryItemId: "book-x", episodeId: null },
        { ebookLocation: "epubcfi(/6/8)" },
      ),
    ).rejects.toThrow();

    const result = await discardProgress(server.client, {
      progressId: "p-x",
      itemId: "book-x",
      episodeId: null,
    });

    expect({ result, log: server.log }).toEqual({ result: "unconfirmed", log: [] });
  });

  it("drops a reading place left waiting by a discard that then deletes, since it may hold the old place", async () => {
    vi.stubGlobal("navigator", { userAgent: "Chrome/1", platform: "test" });
    const server = scriptedDeleteServer("conn-a", ["hang"]);
    usePlayerStore.getState().attach(server.client);
    const discarding = discardProgress(server.client, {
      progressId: "p-x",
      itemId: "book-x",
      episodeId: null,
    });
    await vi.waitFor(() => expect(server.deletes()).toBe(1));

    const saving = changeProgress(
      server.client,
      { libraryItemId: "book-x", episodeId: null },
      { ebookLocation: "epubcfi(/6/8)" },
    );
    await new Promise((resolve) => setTimeout(resolve, 10));
    server.thaw();
    await Promise.all([discarding, saving]);

    expect(server.log).toEqual(["DELETE /api/me/progress/p-x"]);
  });

  it("sends none of the reading places queued during a discard that then deletes", async () => {
    vi.stubGlobal("navigator", { userAgent: "Chrome/1", platform: "test" });
    const server = scriptedDeleteServer("conn-a", ["hang"]);
    usePlayerStore.getState().attach(server.client);
    const queryClient = new QueryClient();
    const save = (place: string) =>
      new MutationObserver(queryClient, ebookPlaceSaves(server.client, "book-x"))
        .mutate(
          issueChange(server.client, { libraryItemId: "book-x", episodeId: null }, { ebookLocation: place }),
        )
        .catch(() => {});
    const discarding = discardProgress(server.client, {
      progressId: "p-x",
      itemId: "book-x",
      episodeId: null,
    });
    await vi.waitFor(() => expect(server.deletes()).toBe(1));

    const saved = [save("epubcfi(/6/8)"), save("epubcfi(/6/10)"), save("epubcfi(/6/12)")];
    await new Promise((resolve) => setTimeout(resolve, 10));
    server.thaw();
    await Promise.all([discarding, ...saved]);

    expect(server.log).toEqual(["DELETE /api/me/progress/p-x"]);
  });

  it("sends reading places queued before a discard ahead of its delete", async () => {
    vi.stubGlobal("navigator", { userAgent: "Chrome/1", platform: "test" });
    const server = scriptedDeleteServer("conn-a", ["ok"]);
    usePlayerStore.getState().attach(server.client);
    let answer = () => {};
    const answered = new Promise<void>((resolve) => {
      answer = resolve;
    });
    const reader = {
      ...server.client,
      command: vi.fn(async (method: "PATCH" | "DELETE", path: string, body: unknown) => {
        if (method === "PATCH") await answered;
        return server.client.command(method, path, body);
      }),
    } as unknown as AbsClient;
    const queryClient = new QueryClient();
    const save = (place: string) =>
      new MutationObserver(queryClient, {
        ...ebookPlaceSaves(reader, "book-x"),
        // The reader refetches progress after each save, before the next one starts.
        onSettled: () => new Promise((resolve) => setTimeout(resolve, 50)),
      }).mutate(issueChange(reader, { libraryItemId: "book-x", episodeId: null }, { ebookLocation: place }));
    const saved = [save("epubcfi(/6/8)"), save("epubcfi(/6/10)")];
    await vi.waitFor(() => expect(reader.command).toHaveBeenCalled());

    const discarding = discardProgress(server.client, {
      progressId: "p-x",
      itemId: "book-x",
      episodeId: null,
    });
    await new Promise((resolve) => setTimeout(resolve, 10));
    answer();
    await Promise.all([discarding, ...saved]);

    expect(server.log).toEqual([
      "PATCH /api/me/progress/book-x",
      "PATCH /api/me/progress/book-x",
      "DELETE /api/me/progress/p-x",
    ]);
  });

  it("sends nothing a discard forgot, after its delete, from a tab whose view of the queue still has it", async () => {
    vi.stubGlobal("navigator", { userAgent: "Chrome/1", platform: "test" });
    const server = scriptedDeleteServer("conn-a", ["ok"]);
    usePlayerStore.getState().attach(server.client);
    outboxFor("conn-a").record(report("old-x", "book-x"));
    const before = localStorage.getItem("abs-web:v1:outbox:conn-a");
    const behind = {
      ...sharedStorage,
      read: (key: string) => (key === "abs-web:v1:outbox:conn-a" ? before : sharedStorage.read(key)),
    };

    await discardProgress(server.client, { progressId: "p-x", itemId: "book-x", episodeId: null });
    const tab = otherTab(server.log, { storage: behind });
    tab.answer();
    await tab.delivering();

    expect(server.log).toEqual(["DELETE /api/me/progress/p-x"]);
  });

  describe("with coordination records an earlier version left", () => {
    /** A discard left pending by that version, with the listening its other tab sent still unanswered. */
    const pendingDiscard = async (block: object) => {
      const hold = outboxFor("conn-a").hold("book-x", null, "p-x");
      hold.abandon();
      await storedCoordination([
        { key: `block:conn-a:${hold.id}`, ...block },
        {
          key: "sending:conn-a:earlier",
          page: "page-gone",
          failed: false,
          reports: [report("old-x", "book-x")],
        },
      ]);
    };

    it("still waits for the earlier version's unanswered listening before deleting", async () => {
      vi.stubGlobal("navigator", { userAgent: "Chrome/1", platform: "test" });
      const server = scriptedDeleteServer("conn-a", ["ok"]);
      await pendingDiscard({ libraryItemId: "book-x", episodeId: null });

      await flushReports(server.client, () => {});

      expect(server.log).toEqual([]);
      expect(outboxFor("conn-a").discardState("book-x", null)).toBe("unconfirmed");
    });

    it("deletes nothing for a discard whose stored phase it cannot read", async () => {
      vi.stubGlobal("navigator", { userAgent: "Chrome/1", platform: "test" });
      const server = scriptedDeleteServer("conn-a", ["ok"]);
      await pendingDiscard({ libraryItemId: "book-x", episodeId: null, phase: "removing" });

      await flushReports(server.client, () => {});

      expect(server.log).toEqual([]);
      expect(outboxFor("conn-a").discardState("book-x", null)).toBe("unconfirmed");
    });

    it("does not keep the progress of an earlier version's discard whose delete may be on its way", async () => {
      vi.stubGlobal("navigator", { userAgent: "Chrome/1", platform: "test" });
      const server = scriptedDeleteServer("conn-a", ["ok"]);
      const hold = outboxFor("conn-a").hold("book-x", null, "p-x");
      hold.abandon();
      await storedCoordination([
        { key: `block:conn-a:${hold.id}`, libraryItemId: "book-x", episodeId: null },
      ]);

      await keepProgress(server.client, "book-x", null);

      expect(outboxFor("conn-a").discardState("book-x", null)).toBe("unconfirmed");
    });

    it("delivers listening past a block whose book cannot be read and that no discard is finishing", async () => {
      vi.stubGlobal("navigator", { userAgent: "Chrome/1", platform: "test" });
      const server = scriptedDeleteServer("conn-a", ["ok"]);
      await storedCoordination([{ key: "block:conn-a:gone", phase: "blocked" }]);
      outboxFor("conn-a").record(report("new-y", "book-y"));

      await flushReports(server.client, () => {});

      expect(server.log).toEqual(["listening book-y@40"]);
    });

    it.each([
      ["deleting", { phase: "deleting" }],
      ["unreadable", { phase: "removing" }],
      ["from the earlier version", {}],
    ])(
      "delivers nothing past a block whose book cannot be read, its phase %s, while its delete may still land",
      async (_, phase) => {
        vi.stubGlobal("navigator", { userAgent: "Chrome/1", platform: "test" });
        const server = scriptedDeleteServer("conn-a", ["ok"]);
        await storedCoordination([{ key: "block:conn-a:gone", ...phase }]);
        outboxFor("conn-a").record(report("new-y", "book-y"));

        await flushReports(server.client, () => {});
        await flushReports(server.client, () => {});

        expect(server.log).toEqual([]);
      },
    );
  });

  it("sends no reading place still waiting its turn once the user discards anyway", async () => {
    vi.stubGlobal("navigator", { userAgent: "Chrome/1", platform: "test" });
    const server = scriptedDeleteServer("conn-a", ["ok"]);
    usePlayerStore.getState().attach(server.client);
    let answer = () => {};
    const answered = new Promise<void>((resolve) => {
      answer = resolve;
    });
    const reader = {
      ...server.client,
      command: vi.fn(async (method: "PATCH" | "DELETE", path: string, body: unknown) => {
        if (method === "PATCH") await answered;
        return server.client.command(method, path, body);
      }),
    } as unknown as AbsClient;
    const queryClient = new QueryClient();
    const save = (place: string) =>
      new MutationObserver(queryClient, ebookPlaceSaves(reader, "book-x")).mutate(
        issueChange(reader, { libraryItemId: "book-x", episodeId: null }, { ebookLocation: place }),
      );
    const saved = [save("epubcfi(/6/8)"), save("epubcfi(/6/10)")];
    await vi.waitFor(() => expect(reader.command).toHaveBeenCalled());
    const hold = outboxFor("conn-a").hold("book-x", null, "p-x");

    await discardAnyway(server.client, "book-x", null);
    hold.settle();
    answer();
    await Promise.all(saved);

    // The first place was already on its way, which discarding anyway accepts.
    expect(server.log).toEqual(["DELETE /api/me/progress/p-x", "PATCH /api/me/progress/book-x"]);
  });
});

describe("a delete that may still be running on the server, with no discard left to finish it", () => {
  const poisoned = { key: "block:conn-a:gone", phase: "deleting" };
  const readablePoisoned = { ...poisoned, libraryItemId: "book-q", episodeId: null };
  const failedSend = (key: string, itemId: string) => ({
    key,
    connectionId: "conn-a",
    page: "page-gone",
    failed: true,
    items: [{ id: `sent-${itemId}`, libraryItemId: itemId, episodeId: null }],
  });
  const discardOf = (client: AbsClient, itemId: string) =>
    discardProgress(client, { progressId: `p-${itemId}`, itemId, episodeId: null });

  it("holds listening until the user confirms a restart they were asked for, then sends it, leaving what came later", async () => {
    vi.stubGlobal("navigator", { userAgent: "Chrome/1", platform: "test" });
    const server = scriptedDeleteServer("conn-a", ["ok", "ok"]);
    usePlayerStore.getState().attach(server.client);
    await storedCoordination([poisoned, failedSend("sending:conn-a:failed-z", "book-z")]);
    outboxFor("conn-a").record(report("new-y", "book-y"));
    await flushReports(server.client, () => {});
    expect({ log: [...server.log], held: await heldDeliveries(server.client) }).toEqual({
      log: [],
      held: { held: 1, restart: null },
    });

    await requestServerRestart(server.client);
    await storedCoordination([failedSend("sending:conn-a:failed-w", "book-w")]);
    expect(await heldDeliveries(server.client)).toEqual({
      held: 1,
      restart: { serverOrigin: "https://abs.example" },
    });
    await confirmServerRestarted(server.client);
    await flushReports(server.client, () => {});

    const held = await heldDeliveries(server.client);
    const later = await discardOf(server.client, "book-w");
    const earlier = await discardOf(server.client, "book-z");

    expect({ log: server.log, held, later, earlier }).toEqual({
      log: ["listening book-y@40", "DELETE /api/me/progress/p-book-z"],
      held: { held: 0, restart: null },
      later: "unconfirmed",
      earlier: "done",
    });
  });

  it("keeps holding a request that failed again, unchanged, after the restart was asked for", async () => {
    vi.stubGlobal("navigator", { userAgent: "Chrome/1", platform: "test" });
    const server = scriptedDeleteServer("conn-a", ["ok"]);
    usePlayerStore.getState().attach(server.client);
    outboxFor("conn-a").record(report("old-z", "book-z"));
    const first = otherTab(server.log, { fails: true });
    const failing = first.delivering();
    first.answer();
    await failing;
    await storedCoordination([readablePoisoned]);

    await requestServerRestart(server.client);
    const again = otherTab(server.log, { fails: true });
    const failingAgain = again.delivering();
    again.answer();
    await failingAgain;
    await confirmServerRestarted(server.client);

    // Sent again after the request, it may have reached the restarted server.
    expect(await discardOf(server.client, "book-z")).toBe("unconfirmed");
  });

  it("goes on sending the listening of another tab whose request it retired", async () => {
    vi.stubGlobal("navigator", { userAgent: "Chrome/1", platform: "test" });
    const server = scriptedDeleteServer("conn-a", []);
    usePlayerStore.getState().attach(server.client);
    outboxFor("conn-a").record(report("old-z", "book-z"));
    const tab = otherTab(server.log);
    const delivering = tab.delivering();
    await vi.waitFor(() => expect(tab.sent()).toBe(true));
    await storedCoordination([readablePoisoned]);

    await requestServerRestart(server.client);
    await confirmServerRestarted(server.client);
    tab.answer();
    await delivering;
    outboxFor("conn-a").record(report("old-z", "book-z", { currentTime: 50, localNow: 60_000 }));
    await flushReports(server.client, () => {});

    expect(server.log.some((line) => line.includes("book-z@50"))).toBe(true);
  });

  it("explains a restart request it cannot read, and lets the user ask again, keeping the unreadable one", async () => {
    vi.stubGlobal("navigator", { userAgent: "Chrome/1", platform: "test" });
    const server = scriptedDeleteServer("conn-a", []);
    usePlayerStore.getState().attach(server.client);
    const unreadable = { key: "restart:conn-a", serverOrigin: 5 };
    await storedCoordination([poisoned, unreadable]);
    outboxFor("conn-a").record(report("new-y", "book-y"));

    const before = await heldDeliveries(server.client);
    await requestServerRestart(server.client);
    const asked = await heldDeliveries(server.client);
    await confirmServerRestarted(server.client);
    await flushReports(server.client, () => {});
    const kept = (await coordinationRecords("restarted:conn-a:")).map(({ key, ...record }) => record);

    expect({ before, asked, log: server.log }).toEqual({
      before: { held: 1, restart: "unreadable" },
      asked: { held: 1, restart: { serverOrigin: "https://abs.example" } },
      log: ["listening book-y@40"],
    });
    expect(kept).toContainEqual(expect.objectContaining({ unreadable: { ...unreadable } }));
  });

  it("keeps holding another tab's request sent again after its sign-in was renewed past the restart request", async () => {
    vi.stubGlobal("navigator", { userAgent: "Chrome/1", platform: "test" });
    const server = scriptedDeleteServer("conn-a", ["ok"]);
    usePlayerStore.getState().attach(server.client);
    outboxFor("conn-a").record(report("old-z", "book-z"));
    let renew = () => {};
    const renewed = new Promise<void>((resolve) => {
      renew = resolve;
    });
    let refused = false;
    const fetcher = vi.fn(async (url: string | URL | Request) => {
      if (String(url).endsWith("/auth/refresh")) {
        await renewed;
        return Response.json({ user: { accessToken: "access-2", refreshToken: "refresh-2" } });
      }
      if (!refused) {
        refused = true;
        return new Response(null, { status: 401 });
      }
      // Still running on the restarted server.
      return new Promise<Response>(() => {});
    });
    const tabClient = createAbsClient({
      connection: {
        ...server.client.connection,
        auth: { kind: "token", accessToken: "access-1", refreshToken: "refresh-1" },
      } as unknown as AbsClient["connection"],
      fetcher,
      saveAuth: () => {},
    });
    const tab = createOutbox("conn-a", sharedStorage, undefined, {
      begin: (connectionId, candidates) => beginPublishing(connectionId, candidates, "page-other"),
      finish: finishSending,
      reattempt,
    });
    void tab.flush(async (sessions, beforeRetry) => {
      const answer = await tabClient.send(
        "POST",
        "/api/session/local-all",
        { sessions },
        localSyncResultSchema,
        undefined,
        beforeRetry,
      );
      return answer.results;
    });
    await vi.waitFor(() => expect(fetcher).toHaveBeenCalledTimes(2));
    await storedCoordination([readablePoisoned]);

    await requestServerRestart(server.client);
    renew();
    await vi.waitFor(() => expect(fetcher).toHaveBeenCalledTimes(3));
    await confirmServerRestarted(server.client);

    expect(await discardOf(server.client, "book-z")).toBe("unconfirmed");
  });

  it.each([
    ["whose book is known", readablePoisoned],
    ["whose book cannot be read", poisoned],
  ])(
    "ends a retired delete %s as a confirmed one, never sending listening it may have deleted",
    async (_, block) => {
      vi.stubGlobal("navigator", { userAgent: "Chrome/1", platform: "test" });
      const server = scriptedDeleteServer("conn-a", []);
      usePlayerStore.getState().attach(server.client);
      outboxFor("conn-a").record(report("old-q", "book-q"));
      const tab = otherTab(server.log, { fails: true });
      const failing = tab.delivering();
      tab.answer();
      await failing;
      await storedCoordination([block]);

      await requestServerRestart(server.client);
      await confirmServerRestarted(server.client);
      await flushReports(server.client, () => {});
      const [restarted] = (await coordinationRecords("restarted:conn-a:")) as {
        dropped?: { report: ListeningReport }[];
      }[];

      // Kept with the request, not sent.
      expect({
        log: server.log,
        dropped: restarted?.dropped?.map((frozen) => frozen.report.libraryItemId),
      }).toEqual({
        log: [],
        dropped: ["book-q"],
      });
    },
  );

  const foreign = { key: "block:conn-b:gone", libraryItemId: "book-q", episodeId: null, phase: "deleting" };
  it.each([
    ["names another account", { connectionId: "conn-b" }],
    ["covers another account's record", { records: [{ key: foreign.key, value: foreign }] }],
    [
      "covers a record whose value names another key",
      { records: [{ key: poisoned.key, value: { ...poisoned, key: "block:conn-a:other" } }] },
    ],
  ])("releases nothing for a restart request that %s, and lets the user ask again", async (_, wrong) => {
    vi.stubGlobal("navigator", { userAgent: "Chrome/1", platform: "test" });
    const server = scriptedDeleteServer("conn-a", []);
    await storedCoordination([
      poisoned,
      foreign,
      {
        key: "restart:conn-a",
        connectionId: "conn-a",
        serverOrigin: "https://abs.example",
        requestedAt: 1,
        records: [{ key: poisoned.key, value: poisoned }],
        ...wrong,
      },
    ]);

    const before = await heldDeliveries(server.client);
    const confirmed = await confirmServerRestarted(server.client).then(
      () => "confirmed",
      () => "refused",
    );
    const stored = (await coordinationRecords("block:")).map(({ key }) => key);
    await requestServerRestart(server.client);
    const asked = await heldDeliveries(server.client);

    expect({ before, confirmed, stored, asked }).toEqual({
      before: { held: 1, restart: "unreadable" },
      confirmed: "refused",
      stored: ["block:conn-a:gone", "block:conn-b:gone"],
      asked: { held: 1, restart: { serverOrigin: "https://abs.example" } },
    });
  });

  it("keeps holding a record that changed after the restart was asked for", async () => {
    vi.stubGlobal("navigator", { userAgent: "Chrome/1", platform: "test" });
    const server = scriptedDeleteServer("conn-a", ["ok"]);
    await storedCoordination([poisoned]);
    outboxFor("conn-a").record(report("new-y", "book-y"));

    await requestServerRestart(server.client);
    await storedCoordination([{ ...poisoned, phase: "removing" }]);
    await confirmServerRestarted(server.client);
    await flushReports(server.client, () => {});

    expect({ log: server.log, held: (await heldDeliveries(server.client)).held }).toEqual({
      log: [],
      held: 1,
    });
  });

  it("releases nothing for a restart confirmed for another server than the one asked about", async () => {
    vi.stubGlobal("navigator", { userAgent: "Chrome/1", platform: "test" });
    const server = scriptedDeleteServer("conn-a", ["ok"]);
    await storedCoordination([poisoned]);
    outboxFor("conn-a").record(report("new-y", "book-y"));
    const moved = {
      ...server.client,
      connection: { ...server.client.connection, serverUrl: "https://other.example" },
    } as unknown as AbsClient;

    await requestServerRestart(server.client);
    await expect(confirmServerRestarted(moved)).rejects.toThrow();
    await flushReports(server.client, () => {});

    expect(server.log).toEqual([]);
  });

  it("releases nothing as time passes, or for a restart confirmed without being asked for first", async () => {
    vi.stubGlobal("navigator", { userAgent: "Chrome/1", platform: "test" });
    const server = scriptedDeleteServer("conn-a", ["ok"]);
    await storedCoordination([poisoned]);
    outboxFor("conn-a").record(report("new-y", "book-y"));

    await expect(confirmServerRestarted(server.client)).rejects.toThrow();
    const later = Date.now() + 30 * 24 * 60 * 60_000;
    const clock = vi.spyOn(Date, "now").mockReturnValue(later);
    await flushReports(server.client, () => {});
    clock.mockRestore();

    expect(server.log).toEqual([]);
  });
});
