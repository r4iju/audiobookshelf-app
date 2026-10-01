import { describe, expect, it } from "vitest";
import { createListeningReport, createOutbox, type ListeningReport, type OutboxStorage } from "./outbox";

function memoryStorage(): OutboxStorage & { data: Map<string, string> } {
  const data = new Map<string, string>();
  return { data, read: (key) => data.get(key) ?? null, write: (key, value) => data.set(key, value) };
}

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
});
