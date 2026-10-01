import { randomId } from "@/lib/random-id";
import type { ListeningReport } from "./outbox";

// Discards and deliveries of listening coordinate across this origin's tabs through IndexedDB, which orders
// read-write transactions on one store across every tab, with or without Web Locks (plain-HTTP origins have none).
// A delivery reads the blocked books and records what it sends in one transaction; a discard blocks its book and
// reads what is being sent in another. Whichever commits first, the other sees it: a blocked book is not sent, and
// listening recorded as being sent keeps the discard from deleting until the server's answer is in.

const DATABASE = "abs-web-coordination";
const STORE = "entries";

export interface Target {
  libraryItemId: string;
  episodeId: string | null;
}

interface Block extends Target {
  key: string;
}

interface Sending {
  key: string;
  /** The page that sends it. */
  page: string;
  /** Its request failed without an answer, so whether and when it reaches the server is unknown. */
  failed: boolean;
  reports: ListeningReport[];
}

/** A report for a blocked book that was being sent when the block was taken. */
export interface InFlight {
  sendingKey: string;
  page: string;
  failed: boolean;
  report: ListeningReport;
}

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

const prefixed = (prefix: string) => IDBKeyRange.bound(prefix, `${prefix}￿`);
const blockPrefix = (connectionId: string) => `block:${connectionId}:`;
const finishedKey = (connectionId: string, holdId: string) => `finished:${connectionId}:${holdId}`;
const sendingPrefix = (connectionId: string) => `sending:${connectionId}:`;
const sameTarget = (a: Target, b: Target) =>
  a.libraryItemId === b.libraryItemId && a.episodeId === b.episodeId;

const CHANNEL = "abs-web:deliveries";
const announcer = typeof BroadcastChannel === "undefined" ? null : new BroadcastChannel(CHANNEL);

function announce() {
  announcer?.postMessage("changed");
}

/** Resolves when any tab records a change in what is being sent, or after `ms`. */
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

/**
 * Records that `candidates` minus any blocked book are about to be sent by this page, and returns those. The
 * record lasts until the server answers (`finishSending`).
 */
export function beginSending(connectionId: string, candidates: ListeningReport[], page: string) {
  return transact<{ sendingKey: string; sending: ListeningReport[] }>((store, finish) => {
    const blocks = store.getAll(prefixed(blockPrefix(connectionId)));
    blocks.onsuccess = () => {
      const blocked = blocks.result as Block[];
      const sending = candidates.filter((report) => !blocked.some((block) => sameTarget(block, report)));
      const sendingKey = `${sendingPrefix(connectionId)}${randomId()}`;
      if (sending.length > 0)
        store.put({ key: sendingKey, page, failed: false, reports: sending } satisfies Sending);
      finish({ sendingKey, sending });
    };
  });
}

/**
 * `answered`: the server answered, or nothing was sent. `failed`: the request failed without an answer. Its reports
 * stay recorded, one entry per report however often it fails, since nothing tells when such a request is done.
 */
export async function finishSending(sendingKey: string, outcome: "answered" | "failed") {
  await transact<void>((store, finish) => {
    const entry = store.get(sendingKey);
    entry.onsuccess = () => {
      store.delete(sendingKey);
      const sending = entry.result as Sending | undefined;
      if (outcome === "failed" && sending) {
        const prefix = sendingKey.slice(0, sendingKey.lastIndexOf(":") + 1);
        for (const report of sending.reports)
          store.put({
            key: `${prefix}failed-${report.id}`,
            page: sending.page,
            failed: true,
            reports: [report],
          } satisfies Sending);
      }
    };
    finish(undefined);
  });
  announce();
}

/** Blocks the target's delivery for a discard, unless that discard has been finished already, and says which. */
export function block(connectionId: string, holdId: string, target: Target) {
  return transact<boolean>((store, finish) => {
    const done = store.get(finishedKey(connectionId, holdId));
    done.onsuccess = () => {
      if (done.result) return finish(false);
      store.put({
        key: `${blockPrefix(connectionId)}${holdId}`,
        libraryItemId: target.libraryItemId,
        episodeId: target.episodeId,
      } satisfies Block);
      finish(true);
    };
  });
}

/** Whether a discard is still to be finished: its block exists and it has not been finished or let go. */
export function stillBlocked(connectionId: string, holdId: string) {
  return transact<boolean>((store, finish) => {
    const blocked = store.get(`${blockPrefix(connectionId)}${holdId}`);
    blocked.onsuccess = () => finish(blocked.result !== undefined);
  });
}

/** Ends a discard's block for good: a tab finishing the same discard later neither blocks nor deletes again. */
export async function finishBlock(connectionId: string, holdId: string) {
  await transact<void>((store, finish) => {
    store.delete(`${blockPrefix(connectionId)}${holdId}`);
    store.put({ key: finishedKey(connectionId, holdId) });
    finish(undefined);
  });
  announce();
}

/** Reports for the target still recorded as being sent. */
export function inFlight(connectionId: string, target: Target) {
  return transact<InFlight[]>((store, finish) => {
    const entries = store.getAll(prefixed(sendingPrefix(connectionId)));
    entries.onsuccess = () =>
      finish(
        (entries.result as Sending[]).flatMap((entry) =>
          entry.reports
            .filter((report) => sameTarget(report, target))
            .map((report) => ({ sendingKey: entry.key, page: entry.page, failed: entry.failed, report })),
        ),
      );
  });
}

/** Stops counting one recorded report against discards of its book, when the user chooses to discard anyway. */
export async function disregard(entry: InFlight) {
  await transact<void>((store, finish) => {
    const stored = store.get(entry.sendingKey);
    stored.onsuccess = () => {
      const sending = stored.result as Sending | undefined;
      if (!sending) return;
      const reports = sending.reports.filter((report) => report.id !== entry.report.id);
      if (reports.length === 0) store.delete(entry.sendingKey);
      else store.put({ ...sending, reports });
    };
    finish(undefined);
  });
}

/** Identifies this page's own deliveries, which it is still waiting on while it lives. */
export const thisPage = randomId();
