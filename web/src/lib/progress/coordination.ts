import { randomId } from "@/lib/random-id";
import type { ListeningReport } from "./outbox";

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

interface Sending {
  key: string;
  /** The page that sends it. */
  page: string;
  /** Its request failed without an answer, so whether and when it reaches the server is unknown. */
  failed: boolean;
  items: Sent[];
}

/** Something for a blocked book that was being sent when the block was taken. */
export interface InFlight {
  sendingKey: string;
  page: string;
  failed: boolean;
  item: Sent;
}

/**
 * Where a discard stands. Delivery for its book is blocked while it is `blocked` or `deleting`. Once its delete is
 * issued (`deleting`) it can no longer be kept, since whether the server has deleted is unknown until it answers.
 */
export type DiscardPhase = "blocked" | "deleting" | "finished" | "kept";

interface Block extends Target {
  key: string;
  phase: "blocked" | "deleting";
}

interface Ended {
  key: string;
  phase: "finished" | "kept";
}

// Listening is reported as cumulative totals per playback session, and the server overwrites a session it already has
// with whatever arrives, in whatever order requests finish. So each version of a session is sent only once the one
// before it has been answered. A version whose request failed without an answer may still land at any time: it is
// frozen, only ever sent again exactly as it was, and the session goes on under a new id that carries just what came
// after it.

interface Totals {
  timeListening: number;
  currentTime: number;
  updatedAt: number;
}

/** A version of a session's listening as sent: `report` under the current publication id. */
export interface Publication {
  /** The session (the id of the reports recorded for it). */
  stream: string;
  /** The recorded report it carries. */
  updatedAt: number;
  report: ListeningReport;
}

interface Stream extends Target {
  key: string;
  id: string;
  /** The id this session's listening is sent under now. */
  publication: string;
  /** What the session's frozen publications carry, which the current one leaves out; null before any froze. */
  base: Totals | null;
  /** The newest recorded report issued, under any publication, or forgotten by a discard: none up to it is sent. */
  issuedUpTo: number;
  /** The current publication's version on its way and not answered yet. */
  open: { report: ListeningReport; totals: Totals; page: string; at: number } | null;
  frozen: Publication[];
}

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
const endedKey = (connectionId: string, holdId: string) => `finished:${connectionId}:${holdId}`;
const sendingPrefix = (connectionId: string) => `sending:${connectionId}:`;
const streamPrefix = (connectionId: string) => `stream:${connectionId}:`;
const sameTarget = (a: Target, b: Target) =>
  a.libraryItemId === b.libraryItemId && a.episodeId === b.episodeId;
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
    readAll<[Block[], Stream[]]>(
      [store.getAll(prefixed(blockPrefix(connectionId))), store.getAll(prefixed(streamPrefix(connectionId)))],
      (blocks, records) => {
        const blocked = (target: Target) => blocks.some((block) => sameTarget(block, target));
        const streams = new Map(records.map((stream) => [stream.id, stream]));
        const changed = new Set<Stream>();
        for (const stream of streams.values())
          if (stream.open && stream.open.page !== page && now - stream.open.at > LOST_MS) {
            freeze(stream);
            changed.add(stream);
          }
        const issued: Publication[] = [];
        for (const report of candidates()) {
          if (blocked(report)) continue;
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
            page,
            failed: false,
            items: sending.map((publication) => publication.report),
          } satisfies Sending);
        finish({ sendingKey, issued, again });
      },
    );
  });
}

/** Records that this page sends `item` now, unless its book is blocked, and gives the record's key if so. */
export function beginSending(connectionId: string, item: Sent, page: string) {
  return transact<string | null>((store, finish) => {
    const blocks = store.getAll(prefixed(blockPrefix(connectionId)));
    blocks.onsuccess = () => {
      if ((blocks.result as Block[]).some((block) => sameTarget(block, item))) return finish(null);
      const sendingKey = `${sendingPrefix(connectionId)}${randomId()}`;
      store.put({ key: sendingKey, page, failed: false, items: [item] } satisfies Sending);
      finish(sendingKey);
    };
  });
}

/**
 * `answered`: the server answered, or nothing was sent. `failed`: the request failed without an answer. Its items
 * stay recorded, one entry per item however often it fails, since nothing tells when such a request is done.
 */
export async function finishSending(sendingKey: string, outcome: "answered" | "failed") {
  const connectionId = sendingKey.slice("sending:".length, sendingKey.lastIndexOf(":"));
  await transact<void>((store, finish) => {
    readAll<[Sending | undefined, Stream[]]>(
      [store.get(sendingKey), store.getAll(prefixed(streamPrefix(connectionId)))],
      (sending, streams) => {
        store.delete(sendingKey);
        if (!sending) return;
        const sent = (report: ListeningReport) => sending.items.some((item) => sameVersion(report, item));
        for (const stream of streams) {
          const before = JSON.stringify(stream);
          if (stream.open && sent(stream.open.report)) {
            if (outcome === "answered") stream.open = null;
            else freeze(stream);
          }
          if (outcome === "answered") stream.frozen = stream.frozen.filter((frozen) => !sent(frozen.report));
          if (JSON.stringify(stream) !== before) store.put(stream);
        }
        if (outcome === "failed") {
          const prefix = sendingKey.slice(0, sendingKey.lastIndexOf(":") + 1);
          for (const item of sending.items)
            store.put({
              key: `${prefix}failed-${item.id}`,
              page: sending.page,
              failed: true,
              items: [item],
            } satisfies Sending);
        }
      },
    );
    finish(undefined);
  });
  announce();
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
  const key = `${blockPrefix(connectionId)}${holdId}`;
  return transact<DiscardPhase>((store, finish) => {
    readAll<[Ended | undefined, Block | undefined, Stream[]]>(
      [
        store.get(endedKey(connectionId, holdId)),
        store.get(key),
        store.getAll(prefixed(streamPrefix(connectionId))),
      ],
      (ended, current, streams) => {
        if (ended) return finish(ended.phase);
        if (current) return finish(current.phase);
        store.put({
          key,
          libraryItemId: target.libraryItemId,
          episodeId: target.episodeId,
          phase: "blocked",
        } satisfies Block);
        for (const report of forgotten) {
          const stream = streams.find((each) => each.id === report.id) ?? newStream(connectionId, report);
          store.put({ ...stream, issuedUpTo: Math.max(stream.issuedUpTo, report.updatedAt) });
        }
        finish("blocked");
      },
    );
  });
}

/** Moves a blocked discard on to deleting, unless it has ended meanwhile, and gives where it stands. */
export function claimDelete(connectionId: string, holdId: string) {
  return transact<DiscardPhase>((store, finish) => {
    readAll<[Ended | undefined, Block | undefined]>(
      [store.get(endedKey(connectionId, holdId)), store.get(`${blockPrefix(connectionId)}${holdId}`)],
      (ended, current) => {
        if (ended) return finish(ended.phase);
        if (!current) throw new Error("A discard is deleting without its block");
        store.put({ ...current, phase: "deleting" } satisfies Block);
        finish("deleting");
      },
    );
  });
}

/**
 * Ends a discard whose delete the server confirmed, for good: a tab finishing the same discard later neither blocks
 * nor deletes again. The versions the book's sessions had frozen hold the old place, and are dropped with it.
 */
export async function finishDelete(connectionId: string, holdId: string, target: Target) {
  await transact<void>((store, finish) => {
    const streams = store.getAll(prefixed(streamPrefix(connectionId)));
    streams.onsuccess = () => {
      for (const stream of streams.result as Stream[])
        if (sameTarget(stream, target)) store.put({ ...stream, frozen: [] });
      store.delete(`${blockPrefix(connectionId)}${holdId}`);
      store.put({ key: endedKey(connectionId, holdId), phase: "finished" } satisfies Ended);
    };
    finish(undefined);
  });
  announce();
}

/** Keeps the progress a discard was to delete, unless its delete has been issued, and gives where it stands. */
export async function keep(connectionId: string, holdId: string) {
  const key = `${blockPrefix(connectionId)}${holdId}`;
  const phase = await transact<DiscardPhase>((store, finish) => {
    readAll<[Ended | undefined, Block | undefined]>(
      [store.get(endedKey(connectionId, holdId)), store.get(key)],
      (ended, current) => {
        if (ended) return finish(ended.phase);
        if (current?.phase === "deleting") return finish("deleting");
        store.delete(key);
        store.put({ key: endedKey(connectionId, holdId), phase: "kept" } satisfies Ended);
        finish("kept");
      },
    );
  });
  announce();
  return phase;
}

/** What is still recorded as being sent for the target. */
export function inFlight(connectionId: string, target: Target) {
  return transact<InFlight[]>((store, finish) => {
    const entries = store.getAll(prefixed(sendingPrefix(connectionId)));
    entries.onsuccess = () =>
      finish(
        (entries.result as Sending[]).flatMap((entry) =>
          entry.items
            .filter((item) => sameTarget(item, target))
            .map((item) => ({ sendingKey: entry.key, page: entry.page, failed: entry.failed, item })),
        ),
      );
  });
}

/** Stops counting one recorded item against discards of its book, when the user chooses to discard anyway. */
export async function disregard(entry: InFlight) {
  await transact<void>((store, finish) => {
    const stored = store.get(entry.sendingKey);
    stored.onsuccess = () => {
      const sending = stored.result as Sending | undefined;
      if (!sending) return;
      const items = sending.items.filter((item) => item.id !== entry.item.id);
      if (items.length === 0) store.delete(entry.sendingKey);
      else store.put({ ...sending, items });
    };
    finish(undefined);
  });
}

/** Identifies this page's own deliveries, which it is still waiting on while it lives. */
export const thisPage = randomId();
