"use client";

import { useEffect, useSyncExternalStore } from "react";
import { flushReports, outboxFor } from "@/lib/progress/sync";
import { useAbs, useSessionStore } from "@/lib/session/store";

const RETRY_MS = 30_000;

/** Delivers queued listening reports for the signed-in connection, now and whenever delivery may succeed again. */
export function useProgressSync() {
  const { client, connection } = useAbs();
  const outbox = outboxFor(connection.id);
  const pending = useSyncExternalStore(
    outbox.subscribe,
    () => outbox.pending().length,
    () => 0,
  );

  // External system: the server; reports are flushed on start, shortly after new ones, when back online and on a timer.
  useEffect(() => {
    const flush = () => void flushReports(client, () => useSessionStore.getState().requireReauth());
    let soon: ReturnType<typeof setTimeout> | undefined;
    const stop = outbox.subscribe(() => {
      clearTimeout(soon);
      soon = setTimeout(flush, 1_000);
    });
    flush();
    const timer = setInterval(() => outbox.pending().length && flush(), RETRY_MS);
    window.addEventListener("online", flush);
    return () => {
      stop();
      clearTimeout(soon);
      clearInterval(timer);
      window.removeEventListener("online", flush);
    };
  }, [client, outbox]);

  return pending;
}
