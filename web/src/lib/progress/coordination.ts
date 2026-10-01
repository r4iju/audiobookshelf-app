import { z } from "zod";
import { randomId } from "@/lib/random-id";
import { type ListeningReport, listeningReportSchema } from "./outbox";

// Discards and what is sent for a book coordinate across this origin's tabs through IndexedDB, which orders
// read-write transactions on one store across every tab, with or without Web Locks (plain-HTTP origins have none).
// A delivery reads the blocked books and records what it sends in one transaction; a discard blocks its book and
// reads what is being sent in another. Whichever commits first, the other sees it: a blocked book is not sent, and
// anything recorded as being sent keeps the discard from deleting until the server's answer is in.

const DATABASE = "abs-web-coordination";
const STORE = "entries";

export interface Target {
  libraryItemId: string;
  episodeId: string | null;
}

/** Something sent for a book or episode: a listening report, or a change to its progress. */
export interface Sent extends Target {
  id: string;
}

/** A change to a book's or episode's progress (reader place, finished), as sent in one PATCH. */
export interface ProgressChange extends Sent {
  change: { isFinished: boolean } | { ebookLocation: string; ebookProgress?: number };
}

const targetSchema = z.object({ libraryItemId: z.string(), episodeId: z.string().nullable() });
const sentSchema = targetSchema.extend({ id: z.string() }).loose();
const keySchema = z.object({ key: z.string() });

const sendingSchema = z.object({
  connectionId: z.string(),
  /** The page that sends it. */
  page: z.string(),
  /** Its request failed without an answer, so whether and when it reaches the server is unknown. */
  failed: z.boolean(),
  /** For a failed request, the record it was sent under, so each failure of the same item is told apart. */
  attempt: z.string().optional(),
  items: z.array(sentSchema),
});
type Sending = Omit<z.infer<typeof sendingSchema>, "items"> & { key: string; items: Sent[] };

/** Something for a blocked book that was being sent when the block was taken. */
export interface InFlight {
  sendingKey: string;
  page: string;
  failed: boolean;
  item: Sent;
}

/**
 * Where a discard stands. Delivery for its book is blocked while it is `blocked`, `deleting` or `unknown`. Once its
 * delete is issued (`deleting`) it can no longer be kept, since whether the server has deleted is unknown until it
 * answers. `unknown`: its stored phase cannot be read, so whether its delete was issued is unknown too.
 */
export type DiscardPhase = "blocked" | "deleting" | "unknown" | "finished" | "kept";

interface Block extends Target {
  key: string;
  phase: "blocked" | "deleting";
}

interface Ended extends Partial<Target> {
  key: string;
  phase: "finished" | "kept";
}

// Listening is reported as cumulative totals per playback session, and the server overwrites a session it already has
// with whatever arrives, in whatever order requests finish. So each version of a session is sent only once the one
// before it has been answered. A version whose request failed without an answer may still land at any time: it is
// frozen, only ever sent again exactly as it was, and the session goes on under a new id that carries just what came
// after it.

const totalsSchema = z.object({ timeListening: z.number(), currentTime: z.number(), updatedAt: z.number() });
// Lazy: outbox.ts imports this module.
const reportSchema = z.lazy(() => listeningReportSchema);

/** A version of a session's listening as sent: `report` under the current publication id. */
export interface Publication {
  /** The session: the id of the reports recorded for it. */
  stream: string;
  /** The `updatedAt` of the recorded report it carries. */
  updatedAt: number;
  report: ListeningReport;
}

const streamSchema = targetSchema.extend({
  key: z.string(),
  id: z.string(),
  publication: z.string(),
  /** What the frozen publications carry; null before any froze. */
  base: totalsSchema.nullable(),
  /** No recorded report up to this is sent: it was issued, or a discard forgot it. */
  issuedUpTo: z.number(),
  /** The current publication's unanswered version. */
  open: z.object({ report: reportSchema, totals: totalsSchema, page: z.string(), at: z.number() }).nullable(),
  frozen: z.array(z.object({ stream: z.string(), updatedAt: z.number(), report: reportSchema })),
});
type Stream = z.infer<typeof streamSchema>;

// Records are read as stored by any version of this client, in any open tab, so each is checked. The version before
// phases were stored kept blocks without a phase, which may be deleting, `finished:` records for discards that deleted, and
// sendings as `reports`. A record that cannot be read counts against delivery and deleting as far as it may reach:
// an unreadable block blocks every book, an unreadable sending is unconfirmed for every book, and an unreadable
// session is not sent.

const earlierSendingSchema = z.object({ page: z.string(), reports: z.array(sentSchema) });

interface StoredBlock {
  key: string;
  /** Null when unreadable: then it blocks every book. */
  target: Target | null;
  phase: "blocked" | "deleting" | "unknown";
}

function readBlock(key: string, raw: unknown): StoredBlock {
  const target = targetSchema.safeParse(raw);
  const phase = z.object({ phase: z.enum(["blocked", "deleting"]).optional() }).safeParse(raw);
  return {
    key,
    target: target.success
      ? { libraryItemId: target.data.libraryItemId, episodeId: target.data.episodeId }
      : null,
    phase: phase.success ? (phase.data.phase ?? "unknown") : "unknown",
  };
}

/** A discard that deleted is never taken for kept: only a record that says `kept` is. */
const readEnded = (raw: unknown): Ended["phase"] =>
  z.object({ phase: z.literal("kept") }).safeParse(raw).success ? "kept" : "finished";

/** A sending as stored, its items null when unreadable. */
type StoredSending = Omit<Sending, "items"> & { items: Sent[] | null };

function readSending(key: string, connectionId: string, raw: unknown): StoredSending {
  const current = sendingSchema.safeParse(raw);
  if (current.success) return { key, ...current.data };
  // The earlier version's sendings are unresolved: nothing tells whether their tab still waits for an answer.
  const earlier = earlierSendingSchema.safeParse(raw);
  if (earlier.success)
    return { key, connectionId, page: earlier.data.page, failed: true, items: earlier.data.reports };
  return { key, connectionId, page: "", failed: true, items: null };
}

/** What a sending carries for the target; for one that cannot be read, a stand-in. */
const sentFor = (sending: StoredSending, target: Target): Sent[] =>
  sending.items
    ? sending.items.filter((item) => sameTarget(item, target))
    : [{ id: "", libraryItemId: target.libraryItemId, episodeId: target.episodeId }];

/** The readable sessions, by id, and the ids of those that cannot be read. */
function readStreams(connectionId: string, raws: unknown[]) {
  const streams = new Map<string, Stream>();
  const unreadable = new Set<string>();
  for (const raw of raws) {
    const parsed = streamSchema.safeParse(raw);
    if (parsed.success) streams.set(parsed.data.id, parsed.data);
    else unreadable.add(storedKey(raw).slice(streamPrefix(connectionId).length));
  }
  return { streams, unreadable };
}

/** A stored record's key, which the store requires of every record. */
const storedKey = (raw: unknown) => keySchema.parse(raw).key;

/** Another page's request left unanswered this long is taken for lost, its tab closed or its request stuck. */
const LOST_MS = 5 * 60_000;

const opened = new WeakMap<IDBFactory, Promise<IDBDatabase>>();

function database() {
  const factory = globalThis.indexedDB;
  if (!factory) return Promise.reject(new Error("This browser keeps no IndexedDB storage"));
  let db = opened.get(factory);
  if (!db) {
    db = new Promise<IDBDatabase>((resolve, reject) => {
      const request = factory.open(DATABASE, 1);
      request.onupgradeneeded = () => request.result.createObjectStore(STORE, { keyPath: "key" });
      request.onsuccess = () => resolve(request.result);
      request.onerror = () => reject(request.error);
    });
    opened.set(factory, db);
    db.catch(() => opened.delete(factory));
  }
  return db;
}

async function transact<T>(work: (store: IDBObjectStore, finish: (value: T) => void) => void): Promise<T> {
  const db = await database();
  return new Promise<T>((resolve, reject) => {
    const transaction = db.transaction(STORE, "readwrite");
    let result: T | undefined;
    work(transaction.objectStore(STORE), (value) => {
      result = value;
    });
    transaction.oncomplete = () => resolve(result as T);
    transaction.onabort = () => reject(transaction.error ?? new Error("IndexedDB transaction aborted"));
  });
}

/** Reads several requests' results, in order, within one transaction. */
function readAll<T extends unknown[]>(
  requests: { [K in keyof T]: IDBRequest<T[K]> },
  then: (...results: T) => void,
) {
  let left = requests.length;
  for (const request of requests)
    request.onsuccess = () => {
      left -= 1;
      if (left === 0) then(...(requests.map((each) => each.result) as T));
    };
}

const prefixed = (prefix: string) => IDBKeyRange.bound(prefix, `${prefix}￿`);
const blockPrefix = (connectionId: string) => `block:${connectionId}:`;
const blockKey = (connectionId: string, holdId: string) => `${blockPrefix(connectionId)}${holdId}`;
const endedPrefix = (connectionId: string) => `ended:${connectionId}:`;
const endedKey = (connectionId: string, holdId: string) => `ended:${connectionId}:${holdId}`;
const earlierFinishedKey = (connectionId: string, holdId: string) => `finished:${connectionId}:${holdId}`;
const sendingPrefix = (connectionId: string) => `sending:${connectionId}:`;
const streamPrefix = (connectionId: string) => `stream:${connectionId}:`;
const sameTarget = (a: Target, b: Target) =>
  a.libraryItemId === b.libraryItemId && a.episodeId === b.episodeId;
const blocks = (block: StoredBlock, target: Target) => !block.target || sameTarget(block.target, target);
const holdOf = (connectionId: string, block: StoredBlock) =>
  block.key.slice(blockPrefix(connectionId).length);
const sameVersion = (a: ListeningReport, b: Sent) =>
  a.id === b.id && "updatedAt" in b && a.updatedAt === b.updatedAt;

const CHANNEL = "abs-web:deliveries";
const announcer = typeof BroadcastChannel === "undefined" ? null : new BroadcastChannel(CHANNEL);

function announce() {
  announcer?.postMessage("changed");
}

/** Resolves when any tab records a change in what is being sent or in a discard, or after `ms`. */
export function deliveryChange(ms: number) {
  return new Promise<void>((resolve) => {
    const channel = typeof BroadcastChannel === "undefined" ? null : new BroadcastChannel(CHANNEL);
    const done = () => {
      clearTimeout(timer);
      channel?.close();
      resolve();
    };
    const timer = setTimeout(done, ms);
    if (channel) channel.onmessage = done;
  });
}

function freeze(stream: Stream) {
  if (!stream.open) return;
  stream.frozen.push({
    stream: stream.id,
    updatedAt: stream.open.totals.updatedAt,
    report: stream.open.report,
  });
  stream.base = stream.open.totals;
  stream.publication = randomId();
  stream.open = null;
}

function newStream(connectionId: string, report: ListeningReport): Stream {
  return {
    key: `${streamPrefix(connectionId)}${report.id}`,
    id: report.id,
    libraryItemId: report.libraryItemId,
    episodeId: report.episodeId,
    publication: report.id,
    base: null,
    issuedUpTo: Number.NEGATIVE_INFINITY,
    open: null,
    frozen: [],
  };
}

/** The recorded report as the current publication's next version. */
function nextVersion(stream: Stream, report: ListeningReport): ListeningReport {
  const { base } = stream;
  if (!base) return { ...report, id: stream.publication };
  return {
    ...report,
    id: stream.publication,
    timeListening: Math.round((report.timeListening - base.timeListening) * 1000) / 1000,
    startTime: base.currentTime,
    startedAt: base.updatedAt,
  };
}

/** What a page is to send: new versions of `candidates` it read, and frozen versions sent again. */
export interface Begun {
  sendingKey: string;
  issued: Publication[];
  again: Publication[];
}

/**
 * Chooses and records, for this page, what to send of the recorded reports (`candidates`, read within the
 * transaction) and of frozen versions, leaving out blocked books and sessions whose last version is still
 * unanswered. The record lasts until the server answers (`finishSending`).
 */
export function beginPublishing(
  connectionId: string,
  candidates: () => ListeningReport[],
  page: string,
  now = Date.now(),
) {
  return transact<Begun>((store, finish) => {
    readAll<[unknown[], unknown[]]>(
      [store.getAll(prefixed(blockPrefix(connectionId))), store.getAll(prefixed(streamPrefix(connectionId)))],
      (blockRecords, streamRecords) => {
        const stored = blockRecords.map((raw) => readBlock(storedKey(raw), raw));
        const blocked = (target: Target) => stored.some((block) => blocks(block, target));
        const { streams, unreadable } = readStreams(connectionId, streamRecords);
        const changed = new Set<Stream>();
        for (const stream of streams.values())
          if (stream.open && stream.open.page !== page && now - stream.open.at > LOST_MS) {
            freeze(stream);
            changed.add(stream);
          }
        const issued: Publication[] = [];
        for (const report of candidates()) {
          if (blocked(report) || unreadable.has(report.id)) continue;
          const stream = streams.get(report.id) ?? newStream(connectionId, report);
          if (stream.open || report.updatedAt <= stream.issuedUpTo) continue;
          const version = nextVersion(stream, report);
          stream.open = {
            report: version,
            totals: {
              timeListening: report.timeListening,
              currentTime: report.currentTime,
              updatedAt: report.updatedAt,
            },
            page,
            at: now,
          };
          stream.issuedUpTo = report.updatedAt;
          streams.set(stream.id, stream);
          changed.add(stream);
          issued.push({ stream: stream.id, updatedAt: report.updatedAt, report: version });
        }
        const again = [...streams.values()].flatMap((stream) => (blocked(stream) ? [] : stream.frozen));
        const sending = [...issued, ...again];
        for (const stream of changed) store.put(stream);
        const sendingKey = `${sendingPrefix(connectionId)}${randomId()}`;
        if (sending.length > 0)
          store.put({
            key: sendingKey,
            connectionId,
            page,
            failed: false,
            items: sending.map((publication) => publication.report),
          } satisfies Sending);
        finish({ sendingKey, issued, again });
      },
    );
  });
}

/**
 * A change issued while discards blocked its book: the discards it waits for (`blockedBy`), and those of its book that
 * had deleted before it was issued (`deleted`, by record key).
 */
export interface Waiting {
  blockedBy: string[];
  deleted: string[];
}

/**
 * Records that this page sends `change`, when the user makes it (`waiting` null) and again while it waits. A change
 * made during a discard waits for that discard, and is dropped if any discard of its book deletes after the change
 * was made, since it may carry the old place. A discard that begins after the change was made does not hold it up
 * before deleting: the change is recorded, and that discard waits for it.
 */
export function beginChange(
  connectionId: string,
  change: ProgressChange,
  page: string,
  waiting: Waiting | null,
) {
  return transact<{ sendingKey: string } | Waiting | "dropped">((store, finish) => {
    readAll<[unknown[], unknown[], unknown[]]>(
      [
        store.getAll(prefixed(blockPrefix(connectionId))),
        store.getAll(prefixed(endedPrefix(connectionId))),
        store.getAll(prefixed(earlierFinishedKey(connectionId, ""))),
      ],
      (blockRecords, endedRecords, earlierFinished) => {
        const deleted = [...endedRecords, ...earlierFinished]
          .filter((raw) => {
            if (readEnded(raw) !== "finished") return false;
            // A record without its book, from an earlier version, may be this one's.
            const target = targetSchema.safeParse(raw);
            return !target.success || sameTarget(target.data, change);
          })
          .map(storedKey);
        if (waiting && deleted.some((key) => !waiting.deleted.includes(key))) return finish("dropped");
        const blocking = blockRecords
          .map((raw) => readBlock(storedKey(raw), raw))
          .filter(
            (block) =>
              blocks(block, change) &&
              (!waiting ||
                block.phase !== "blocked" ||
                waiting.blockedBy.includes(holdOf(connectionId, block))),
          )
          .map((block) => holdOf(connectionId, block));
        if (blocking.length > 0)
          return finish({
            blockedBy: [...new Set([...(waiting?.blockedBy ?? []), ...blocking])],
            deleted: waiting?.deleted ?? deleted,
          });
        const sendingKey = `${sendingPrefix(connectionId)}${randomId()}`;
        store.put({ key: sendingKey, connectionId, page, failed: false, items: [change] } satisfies Sending);
        finish({ sendingKey });
      },
    );
  });
}

/**
 * `answered`: the server answered, or nothing was sent. `failed`: the request failed without an answer. Its items
 * stay recorded, one entry per item holding its latest failure, since nothing tells when such a request is done.
 */
export async function finishSending(sendingKey: string, outcome: "answered" | "failed") {
  await transact<void>((store, finish) => {
    const recorded = store.get(sendingKey);
    recorded.onsuccess = () => {
      if (recorded.result === undefined) return;
      const parsed = sendingSchema.safeParse(recorded.result);
      // Unreadable, it stays as stored: unconfirmed for every book.
      if (!parsed.success) return;
      const sending = parsed.data;
      store.delete(sendingKey);
      const records = store.getAll(prefixed(streamPrefix(sending.connectionId)));
      records.onsuccess = () => {
        const { streams } = readStreams(sending.connectionId, records.result);
        const sent = (report: ListeningReport) => sending.items.some((item) => sameVersion(report, item));
        for (const stream of streams.values()) {
          const before = JSON.stringify(stream);
          if (stream.open && sent(stream.open.report)) {
            if (outcome === "answered") stream.open = null;
            else freeze(stream);
          }
          if (outcome === "answered") stream.frozen = stream.frozen.filter((frozen) => !sent(frozen.report));
          if (JSON.stringify(stream) !== before) store.put(stream);
        }
        if (outcome === "failed")
          for (const item of sending.items)
            store.put({
              ...sending,
              key: `${sendingPrefix(sending.connectionId)}failed-${item.id}`,
              failed: true,
              attempt: sendingKey,
              items: [item],
            } satisfies Sending);
      };
    };
    finish(undefined);
  });
  announce();
}

/** The records that say where a discard stands, to read with `readPhase`. */
const discardRecords = (
  store: IDBObjectStore,
  connectionId: string,
  holdId: string,
): [IDBRequest<unknown>, IDBRequest<unknown>, IDBRequest<unknown>] => [
  store.get(endedKey(connectionId, holdId)),
  store.get(earlierFinishedKey(connectionId, holdId)),
  store.get(blockKey(connectionId, holdId)),
];

/** Where a discard stands as stored, or null before it is blocked. */
function readPhase(
  blockKey: string,
  ended: unknown,
  earlierFinished: unknown,
  block: unknown,
): DiscardPhase | null {
  if (ended !== undefined) return readEnded(ended);
  if (earlierFinished !== undefined) return "finished";
  return block === undefined ? null : readBlock(blockKey, block).phase;
}

/**
 * Blocks the target's delivery for a discard, unless that discard has ended, and gives where it stands. The reports
 * the discard forgot (`forgotten`) are never sent afterwards, though a tab that has not seen them go still has them.
 */
export function block(
  connectionId: string,
  holdId: string,
  target: Target,
  forgotten: ListeningReport[] = [],
) {
  const key = blockKey(connectionId, holdId);
  return transact<DiscardPhase>((store, finish) => {
    readAll<[unknown, unknown, unknown, unknown[]]>(
      [...discardRecords(store, connectionId, holdId), store.getAll(prefixed(streamPrefix(connectionId)))],
      (ended, earlierFinished, current, streamRecords) => {
        const phase = readPhase(key, ended, earlierFinished, current);
        if (phase) return finish(phase);
        store.put({
          key,
          libraryItemId: target.libraryItemId,
          episodeId: target.episodeId,
          phase: "blocked",
        } satisfies Block);
        const { streams, unreadable } = readStreams(connectionId, streamRecords);
        for (const report of forgotten) {
          if (unreadable.has(report.id)) continue;
          const stream = streams.get(report.id) ?? newStream(connectionId, report);
          store.put({ ...stream, issuedUpTo: Math.max(stream.issuedUpTo, report.updatedAt) });
        }
        finish("blocked");
      },
    );
  });
}

/**
 * Moves a blocked discard on to deleting, unless it has ended meanwhile or something for its book is being sent
 * (then it stays `blocked`), and gives where it stands.
 */
export function claimDelete(connectionId: string, holdId: string, target: Target) {
  const key = blockKey(connectionId, holdId);
  return transact<DiscardPhase>((store, finish) => {
    readAll<[unknown, unknown, unknown, unknown[]]>(
      [...discardRecords(store, connectionId, holdId), store.getAll(prefixed(sendingPrefix(connectionId)))],
      (ended, earlierFinished, current, sendings) => {
        const phase = readPhase(key, ended, earlierFinished, current);
        if (phase === "finished" || phase === "kept") return finish(phase);
        if (!phase) throw new Error("A discard is deleting without its block");
        if (
          sendings.some((raw) => sentFor(readSending(storedKey(raw), connectionId, raw), target).length > 0)
        )
          return finish("blocked");
        store.put({
          key,
          libraryItemId: target.libraryItemId,
          episodeId: target.episodeId,
          phase: "deleting",
        } satisfies Block);
        finish("deleting");
      },
    );
  });
}

/**
 * Ends a discard whose delete the server confirmed, for good: a tab finishing the same discard later neither blocks
 * nor deletes again. The book's frozen versions carry the old place, and are dropped.
 */
export async function finishDelete(connectionId: string, holdId: string, target: Target) {
  await transact<void>((store, finish) => {
    const records = store.getAll(prefixed(streamPrefix(connectionId)));
    records.onsuccess = () => {
      for (const stream of readStreams(connectionId, records.result).streams.values())
        if (sameTarget(stream, target)) store.put({ ...stream, frozen: [] });
      store.delete(blockKey(connectionId, holdId));
      store.put({
        key: endedKey(connectionId, holdId),
        phase: "finished",
        libraryItemId: target.libraryItemId,
        episodeId: target.episodeId,
      } satisfies Ended);
    };
    finish(undefined);
  });
  announce();
}

/** Keeps the progress a discard was to delete, unless its delete may have been issued, and gives where it stands. */
export async function keep(connectionId: string, holdId: string) {
  const key = blockKey(connectionId, holdId);
  const phase = await transact<DiscardPhase>((store, finish) => {
    readAll<[unknown, unknown, unknown]>(discardRecords(store, connectionId, holdId), (...stored) => {
      const current = readPhase(key, ...stored);
      if (current !== "blocked" && current !== null) return finish(current);
      store.delete(key);
      store.put({ key: endedKey(connectionId, holdId), phase: "kept" } satisfies Ended);
      finish("kept");
    });
  });
  announce();
  return phase;
}

/** Whether a recorded sending still counts: a discard that went ahead anyway has stopped counting it. */
export function isSending(sendingKey: string) {
  return transact<boolean>((store, finish) => {
    const stored = store.getKey(sendingKey);
    stored.onsuccess = () => finish(stored.result !== undefined);
  });
}

/**
 * Removes blocks whose book cannot be read, that none of `holdIds` is finishing and whose delete was never issued:
 * nothing would ever end them, and they would hold back every book. One whose delete may have been issued stays,
 * since that delete may still land after listening sent past it.
 */
export function releaseUnreadableBlocks(connectionId: string, holdIds: string[]) {
  return transact<void>((store, finish) => {
    const records = store.getAll(prefixed(blockPrefix(connectionId)));
    records.onsuccess = () => {
      for (const raw of records.result) {
        const block = readBlock(storedKey(raw), raw);
        if (!block.target && block.phase === "blocked" && !holdIds.includes(holdOf(connectionId, block)))
          store.delete(block.key);
      }
    };
    finish(undefined);
  });
}

// Server 2.30 gives no way to learn that a request it is still handling has finished, but a restart of the server
// ends them all. So a delete that may still be running, with no discard left to finish it, and requests that failed
// without an answer, end in two steps: the user asks to restart, which records exactly those records as they are
// then, and after restarting the server confirms it, which retires only the records still exactly as recorded.
// Anything recorded or changed after the request may have reached the restarted server, and stays.

const restartKey = (connectionId: string) => `restart:${connectionId}`;
const restartedPrefix = (connectionId: string) => `restarted:${connectionId}:`;

const restartSchema = z.object({
  key: z.string(),
  connectionId: z.string(),
  /** The server whose restart ends the recorded requests. */
  serverOrigin: z.string(),
  requestedAt: z.number(),
  records: z.array(z.object({ key: z.string(), value: z.unknown() })),
});
type Restart = z.infer<typeof restartSchema>;

/** Blocks whose delete may have been issued, that none of `holdIds` is finishing: only a restart ends them. */
const unfinishedBlocks = (connectionId: string, blockRecords: unknown[], holdIds: string[]) =>
  blockRecords.filter((raw) => {
    const block = readBlock(storedKey(raw), raw);
    return block.phase !== "blocked" && !holdIds.includes(holdOf(connectionId, block));
  });

interface Held {
  held: number;
  restart: { serverOrigin: string } | "unreadable" | null;
}

/**
 * Where the account's held deliveries stand: how many unfinished deletes hold them, and the restart asked for, if any.
 * `unreadable`: one was asked for, but which records it covers cannot be read, so it releases nothing.
 */
export function heldByUnfinishedDeletes(connectionId: string, holdIds: string[]) {
  return transact<Held>((store, finish) => {
    readAll<[unknown[], unknown]>(
      [store.getAll(prefixed(blockPrefix(connectionId))), store.get(restartKey(connectionId))],
      (blockRecords, stored) => {
        const restart = restartSchema.safeParse(stored);
        finish({
          held: unfinishedBlocks(connectionId, blockRecords, holdIds).length,
          restart: restart.success
            ? { serverOrigin: restart.data.serverOrigin }
            : stored === undefined
              ? null
              : "unreadable",
        });
      },
    );
  });
}

/**
 * Records, before the user restarts `serverOrigin`, exactly which records its restart is to end: unfinished deletes
 * and every request recorded as sent, except this page's own still waiting for their answers. A readable request
 * already made stays as it was; an unreadable one is set aside, kept, for this one.
 */
export function requestRestart(connectionId: string, serverOrigin: string, holdIds: string[], page: string) {
  return transact<void>((store, finish) => {
    readAll<[unknown, unknown[], unknown[]]>(
      [
        store.get(restartKey(connectionId)),
        store.getAll(prefixed(blockPrefix(connectionId))),
        store.getAll(prefixed(sendingPrefix(connectionId))),
      ],
      (existing, blockRecords, sendings) => {
        if (restartSchema.safeParse(existing).success) return;
        const requestedAt = Date.now();
        if (existing !== undefined)
          store.put({
            key: `${restartedPrefix(connectionId)}unreadable-${requestedAt}`,
            unreadable: existing,
          });
        const covered = [
          ...unfinishedBlocks(connectionId, blockRecords, holdIds),
          ...sendings.filter((raw) => {
            const sending = readSending(storedKey(raw), connectionId, raw);
            return sending.failed || sending.page !== page;
          }),
        ];
        store.put({
          key: restartKey(connectionId),
          connectionId,
          serverOrigin,
          requestedAt,
          records: covered.map((value) => ({ key: storedKey(value), value })),
        } satisfies Restart);
      },
    );
    finish(undefined);
  });
}

/**
 * Retires, once the user confirms restarting the server the request named, the recorded records still exactly as
 * they were. Listening another page was sending under a retired record is sent again, as after a failure, since that
 * page's answer no longer finds the record. The request is kept, as a record of what was retired.
 */
export async function confirmRestart(connectionId: string, serverOrigin: string) {
  await transact<void>((store, finish) => {
    const stored = store.get(restartKey(connectionId));
    stored.onsuccess = () => {
      // Thrown here, the error aborts the transaction, so nothing is retired.
      const restart = restartSchema.safeParse(stored.result);
      if (!restart.success) throw new Error("No readable restart of this server was asked for");
      if (restart.data.serverOrigin !== serverOrigin)
        throw new Error("The restart asked for was of another server");
      const { records } = restart.data;
      readAll<[unknown[], ...unknown[]]>(
        [store.getAll(prefixed(streamPrefix(connectionId))), ...records.map(({ key }) => store.get(key))],
        (streamRecords, ...current) => {
          const retired = records.filter(
            ({ value }, index) => JSON.stringify(current[index]) === JSON.stringify(value),
          );
          const items = retired.flatMap(({ key, value }) =>
            key.startsWith(sendingPrefix(connectionId)) ? readSending(key, connectionId, value).items : [],
          );
          for (const stream of readStreams(connectionId, streamRecords).streams.values()) {
            const open = stream.open?.report;
            if (open && items.some((item) => item !== null && sameVersion(open, item))) {
              freeze(stream);
              store.put(stream);
            }
          }
          for (const { key } of retired) store.delete(key);
          store.delete(restartKey(connectionId));
          store.put({
            ...restart.data,
            key: `${restartedPrefix(connectionId)}${restart.data.requestedAt}`,
            retired: retired.map(({ key }) => key),
          });
        },
      );
    };
    finish(undefined);
  });
  announce();
}

/** What is still recorded as being sent for the target. */
export function inFlight(connectionId: string, target: Target) {
  return transact<InFlight[]>((store, finish) => {
    const entries = store.getAll(prefixed(sendingPrefix(connectionId)));
    entries.onsuccess = () =>
      finish(
        entries.result.flatMap((raw) => {
          const entry = readSending(storedKey(raw), connectionId, raw);
          return sentFor(entry, target).map((item) => ({
            sendingKey: entry.key,
            page: entry.page,
            failed: entry.failed,
            item,
          }));
        }),
      );
  });
}

/** Stops counting one recorded item against discards of its book, when the user chooses to discard anyway. */
export async function disregard(connectionId: string, entry: InFlight) {
  await transact<void>((store, finish) => {
    const stored = store.get(entry.sendingKey);
    stored.onsuccess = () => {
      if (stored.result === undefined) return;
      const sending = readSending(entry.sendingKey, connectionId, stored.result);
      const items = sending.items?.filter((item) => item.id !== entry.item.id) ?? [];
      if (items.length === 0) store.delete(entry.sendingKey);
      else store.put({ ...sending, items } satisfies Sending);
    };
    finish(undefined);
  });
}

/** Identifies this page's own deliveries, which it is still waiting on while it lives. */
export const thisPage = randomId();
