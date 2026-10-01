import { afterEach, describe, expect, it, vi } from "vitest";
import { beginPublishing, finishSending, reattempt } from "./coordination";
import { createListeningReport, createOutbox, type ListeningReport, type OutboxStorage } from "./outbox";

function memoryStorage(): OutboxStorage & { data: Map<string, string> } {
  const data = new Map<string, string>();
  return {
    data,
    read: (key) => data.get(key) ?? null,
    write: (key, value) => data.set(key, value),
    remove: (key) => data.delete(key),
    keys: (prefix) => [...data.keys()].filter((key) => key.startsWith(prefix)),
  };
}

/** Storage for a second tab; once armed, its next change is preceded by whatever the other tab does at that moment. */
function interleaving(shared: OutboxStorage) {
  let meanwhile: (() => void) | null = null;
  const first = () => {
    const step = meanwhile;
    meanwhile = null;
    step?.();
  };
  const storage: OutboxStorage = {
    ...shared,
    write: (key, value) => {
      first();
      shared.write(key, value);
    },
    remove: (key) => {
      first();
      shared.remove(key);
    },
  };
  return { storage, arm: (step: () => void) => (meanwhile = step) };
}

/** A recorded report sent as it is, as the first version of its session. */
const asPublished = (report: ListeningReport) => ({ stream: report.id, updatedAt: report.updatedAt, report });

const base = {
  id: "s1",
  libraryItemId: "li1",
  episodeId: null,
  libraryId: "lib1",
  mediaType: "book" as const,
  displayTitle: "The Long Tide",
  displayAuthor: "Mira Vale",
  duration: 90,
  startTime: 0,
  startedAt: 1_000,
};

describe("listening report", () => {
  it("dates reports in server time and never moves updatedAt backwards", () => {
    const first = createListeningReport(base, {
      currentTime: 10,
      timeListening: 10,
      localNow: 50_000,
      serverOffset: 2_000,
    });
    expect(first.updatedAt).toBe(52_000);
    expect(first.date).toBe("1970-01-01");
    expect(first.dayOfWeek).toBe("Thursday");
    const second = createListeningReport(
      base,
      { currentTime: 11, timeListening: 11, localNow: 40_000, serverOffset: 2_000 },
      first,
    );
    expect(second.updatedAt).toBe(52_001);
  });
});

describe("progress outbox", () => {
  const report = (currentTime: number, updatedAt: number): ListeningReport => ({
    ...createListeningReport(base, {
      currentTime,
      timeListening: currentTime,
      localNow: updatedAt,
      serverOffset: 0,
    }),
  });

  it("keeps only the newest cumulative report per session and survives a reload", () => {
    const storage = memoryStorage();
    const outbox = createOutbox("conn-a", storage);
    outbox.record(report(10, 1_000));
    outbox.record(report(20, 2_000));
    expect(
      createOutbox("conn-a", storage)
        .pending()
        .map((entry) => entry.currentTime),
    ).toEqual([20]);
    expect(createOutbox("conn-b", storage).pending()).toEqual([]);
  });

  it("removes delivered reports but keeps one that changed while sending", async () => {
    const storage = memoryStorage();
    const outbox = createOutbox("conn-a", storage);
    outbox.record(report(10, 1_000));
    outbox.record({ ...report(5, 1_000), id: "s2" });
    const result = await outbox.flush(async (sessions) => {
      outbox.record({ ...report(30, 3_000), id: "s2" });
      return sessions.map((session) => ({ id: session.id, success: true }));
    });
    expect(result).toEqual({ kind: "sent", delivered: 2 });
    expect(outbox.pending().map((entry) => [entry.id, entry.currentTime])).toEqual([["s2", 30]]);
  });

  it("keeps everything when delivery fails and reports why", async () => {
    const outbox = createOutbox("conn-a", memoryStorage());
    outbox.record(report(10, 1_000));
    const result = await outbox.flush(async () => {
      throw new Error("offline");
    });
    expect(result.kind).toBe("failed");
    expect(outbox.pending()).toHaveLength(1);
  });

  it("sends nothing and reports a failure when the browser will not record what is being sent", async () => {
    const outbox = createOutbox("conn-a", memoryStorage(), undefined, {
      begin: async () => {
        throw new Error("IndexedDB refused");
      },
      finish: async () => {},
      reattempt: async () => {},
    });
    outbox.record(report(10, 1_000));
    let sent = false;
    const result = await outbox.flush(async () => {
      sent = true;
      return [];
    });
    expect({ kind: result.kind, sent }).toEqual({ kind: "failed", sent: false });
    expect(outbox.pending()).toHaveLength(1);
  });

  it("sends exactly what it recorded as being sent, though another tab advanced the report meanwhile", async () => {
    const storage = memoryStorage();
    let recorded: ListeningReport[] = [];
    const outbox = createOutbox("conn-a", storage, undefined, {
      begin: async (_connectionId, candidates) => {
        recorded = structuredClone(candidates());
        createOutbox("conn-a", storage).record(report(30, 3_000));
        return { sendingKey: "k", issued: recorded.map(asPublished), again: [] };
      },
      finish: async () => {},
      reattempt: async () => {},
    });
    outbox.record(report(10, 1_000));
    let sent: ListeningReport[] = [];
    await outbox.flush(async (sessions) => {
      sent = sessions;
      return sessions.map((session) => ({ id: session.id, success: true }));
    });
    expect(sent).toEqual(recorded);
    expect(outbox.pending().map((entry) => entry.currentTime)).toEqual([30]);
  });

  it("keeps what the server answered though the browser then fails to note that it was answered", async () => {
    const outbox = createOutbox("conn-a", memoryStorage(), undefined, {
      begin: async (_connectionId, candidates) => ({
        sendingKey: "k",
        issued: candidates().map(asPublished),
        again: [],
      }),
      finish: async () => {
        throw new Error("IndexedDB refused");
      },
      reattempt: async () => {},
    });
    outbox.record(report(10, 1_000));
    const result = await outbox.flush(async (sessions) =>
      sessions.map((session) => ({ id: session.id, success: true })),
    );
    expect(result).toEqual({ kind: "sent", delivered: 1 });
    expect(outbox.pending()).toEqual([]);
  });

  it("drops a report the server rejects for good so it cannot block the queue", async () => {
    const outbox = createOutbox("conn-a", memoryStorage());
    outbox.record(report(10, 1_000));
    await outbox.flush(async (sessions) =>
      sessions.map((session) => ({ id: session.id, success: false, error: "Media item not found" })),
    );
    expect(outbox.pending()).toEqual([]);
  });

  it("notifies listeners when the queue changes", () => {
    const outbox = createOutbox("conn-a", memoryStorage());
    const sizes: number[] = [];
    const stop = outbox.subscribe(() => sizes.push(outbox.pending().length));
    outbox.record(report(10, 1_000));
    stop();
    outbox.record({ ...report(10, 1_000), id: "s3" });
    expect(sizes).toEqual([1]);
  });

  it("forgets unsent listening for one book or episode whose progress was discarded", () => {
    const storage = memoryStorage();
    const outbox = createOutbox("conn-a", storage);
    outbox.record(report(10, 1_000));
    outbox.record({ ...report(10, 1_000), id: "s2", libraryItemId: "li2" });
    outbox.record({ ...report(10, 1_000), id: "s3", episodeId: "ep1" });
    outbox.forget("li1", null);
    expect(
      createOutbox("conn-a", storage)
        .pending()
        .map((entry) => entry.id),
    ).toEqual(["s2", "s3"]);
  });

  describe("a session's cumulative listening", () => {
    afterEach(() => {
      vi.useRealTimers();
    });

    const answer = async (sessions: ListeningReport[]) =>
      sessions.map((session) => ({ id: session.id, success: true }));
    /** Another tab, on the same browser storage, whose request the server answers only when the test says so. */
    const otherTab = (storage: OutboxStorage) => {
      const outbox = createOutbox("conn-a", storage, undefined, {
        begin: (connectionId, candidates) => beginPublishing(connectionId, candidates, "page-other"),
        finish: finishSending,
        reattempt,
      });
      let release = () => {};
      const released = new Promise<void>((resolve) => {
        release = resolve;
      });
      const sent: ListeningReport[] = [];
      const flushing = outbox.flush(async (sessions) => {
        sent.push(...sessions);
        await released;
        return answer(sessions);
      });
      return { sent, release, flushing };
    };

    it("goes on under another session after a request fails without an answer, so that one landing late lowers nothing", async () => {
      const outbox = createOutbox("conn-a", memoryStorage());
      outbox.record(report(10, 1_000));
      let failed: ListeningReport[] = [];
      await outbox.flush(async (sessions) => {
        failed = structuredClone(sessions);
        throw new Error("offline");
      });
      outbox.record(report(30, 3_000));

      const sent: ListeningReport[] = [];
      await outbox.flush(async (sessions) => {
        sent.push(...sessions);
        return answer(sessions);
      });

      // The failed version is only ever sent again as it was. What came after it is a session of its own.
      const [rest] = sent.filter((session) => session.id !== "s1");
      expect(sent.filter((session) => session.id === "s1")).toEqual(failed);
      expect(rest).toEqual({
        ...report(30, 3_000),
        id: rest?.id,
        timeListening: 20,
        startTime: 10,
        startedAt: 1_000,
      });
      expect(outbox.pending()).toEqual([]);
    });

    it("sends no newer version of a session while another tab's request for it is unanswered", async () => {
      const storage = memoryStorage();
      const outbox = createOutbox("conn-a", storage);
      outbox.record(report(10, 1_000));
      const tab = otherTab(storage);
      await vi.waitFor(() => expect(tab.sent).toHaveLength(1));
      outbox.record(report(30, 3_000));

      const sent: ListeningReport[] = [];
      const send = async (sessions: ListeningReport[]) => {
        sent.push(...sessions);
        return answer(sessions);
      };
      await outbox.flush(send);
      expect(sent).toEqual([]);
      tab.release();
      await tab.flushing;
      await outbox.flush(send);

      expect(sent).toEqual([report(30, 3_000)]);
    });

    it("goes on under another session when another tab's request for it stays unanswered", async () => {
      vi.useFakeTimers({ toFake: ["Date"] });
      const storage = memoryStorage();
      const outbox = createOutbox("conn-a", storage);
      outbox.record(report(10, 1_000));
      const tab = otherTab(storage);
      await vi.waitFor(() => expect(tab.sent).toHaveLength(1));
      outbox.record(report(30, 3_000));
      // That tab was closed, or its request is stuck.
      vi.advanceTimersByTime(10 * 60_000);

      const sent: ListeningReport[] = [];
      await outbox.flush(async (sessions) => {
        sent.push(...sessions);
        return answer(sessions);
      });

      const [rest] = sent.filter((session) => session.id !== "s1");
      expect(sent.filter((session) => session.id === "s1")).toEqual(tab.sent);
      expect(rest).toMatchObject({ timeListening: 20, startTime: 10, currentTime: 30 });
    });
  });

  describe("holds taken by two tabs at the same moment", () => {
    const queued = (id: string, libraryItemId: string) => ({ ...report(10, 1_000), id, libraryItemId });
    const deliveredItems = async (outbox: ReturnType<typeof createOutbox>) => {
      const sent: string[] = [];
      await outbox.flush(async (sessions) => {
        sent.push(...sessions.map((session) => session.libraryItemId));
        return sessions.map((session) => ({ id: session.id, success: true }));
      });
      return sent;
    };

    it("keeps both when they are taken together", async () => {
      const shared = memoryStorage();
      const other = createOutbox("conn-a", shared);
      const tab = interleaving(shared);
      tab.arm(() => other.hold("book-z", null, "p-z"));
      createOutbox("conn-a", tab.storage).hold("book-x", null, "p-x");
      other.record(queued("x", "book-x"));
      other.record(queued("z", "book-z"));

      expect(await deliveredItems(other)).toEqual([]);
    });

    it("keeps the other tab's when one is released", async () => {
      const shared = memoryStorage();
      const other = createOutbox("conn-a", shared);
      const tab = interleaving(shared);
      const held = createOutbox("conn-a", tab.storage).hold("book-x", null, "p-x");
      tab.arm(() => other.hold("book-z", null, "p-z"));
      held.settle();
      other.record(queued("x", "book-x"));
      other.record(queued("z", "book-z"));

      expect(await deliveredItems(other)).toEqual(["book-x"]);
    });
  });
});
