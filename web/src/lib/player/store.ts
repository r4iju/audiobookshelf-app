import { z } from "zod";
import { create } from "zustand";
import { type AbsClient, AbsError } from "@/lib/abs/client";
import { chapterSchema } from "@/lib/abs/schemas";
import { createListeningReport, type ListeningReport, type ReportIdentity } from "@/lib/progress/outbox";
import { outboxFor } from "@/lib/progress/sync";
import { randomId } from "@/lib/random-id";
import { useSettingsStore } from "@/lib/settings/store";
import { readStored, removeStored, writeStored } from "@/lib/storage/local";
import { closePlayback, openPlayback } from "./api";
import { resumeRewind } from "./rewind";
import { chapterIndexAt } from "./timeline";

export const playerMediaSchema = z.object({
  itemId: z.string(),
  episodeId: z.string().nullable(),
  libraryId: z.string(),
  mediaType: z.enum(["book", "podcast"]),
  title: z.string(),
  author: z.string(),
  coverUrl: z.string().nullable(),
  duration: z.number(),
  chapters: z.array(chapterSchema),
});
export type PlayerMedia = z.infer<typeof playerMediaSchema>;

export interface PlayerTrack {
  url: string;
  startOffset: number;
  duration: number;
  hls: boolean;
}

interface Source {
  serverSessionId: string;
  tracks: PlayerTrack[];
  /** A retry must produce actual audio before another automatic retry is allowed. */
  recovery: boolean;
}

interface Listening {
  identity: ReportIdentity;
  timeListening: number;
  serverOffset: number;
  lastTick: number | null;
  lastReportedAt: number;
  last: ListeningReport | null;
}

export type Sleep = { kind: "off" } | { kind: "until"; endsAt: number } | { kind: "chapter-end"; at: number };

export type PlayerStatus = "paused" | "loading" | "playing";

export type Player =
  | { phase: "idle" }
  | {
      phase: "active";
      media: PlayerMedia;
      source: Source | null;
      status: PlayerStatus;
      error: "autoplay-blocked" | "media-failed" | "start-failed" | null;
      errorDetail?: string;
      currentTime: number;
      /** Replaced when the position changes for a reason other than playback, so the audio element moves there. */
      seekTo: { time: number };
    };

export interface PlayRequest {
  media: PlayerMedia;
  startTime?: number;
}

interface PlayerStore {
  player: Player;
  sleep: Sleep;
  connectionId: string | null;
  client: AbsClient | null;
  listening: Listening | null;
  /** When playback last paused without a new place being chosen, so resuming can step back as the native apps do. */
  pausedAt: number | null;
  attach: (client: AbsClient) => void;
  detach: () => void;
  play: (request: PlayRequest) => Promise<void>;
  resume: () => Promise<void>;
  pause: () => void;
  seek: (time: number) => void;
  jump: (seconds: number) => void;
  stop: () => Promise<void>;
  /** After its progress is discarded: drops this device's unsent listening and goes back to the start. */
  startOver: (target: { connectionId: string; itemId: string; episodeId: string | null }) => Promise<void>;
  setSleep: (sleep: Sleep) => void;
  /** Records listening so far, for example before the page is hidden or closed. */
  checkpoint: () => void;
  // Events from the audio element.
  onTime: (time: number) => void;
  onPlaying: () => void;
  onPaused: () => void;
  /** A file of the book ended; `next` is where the following file starts, or null after the last. */
  onFileEnded: (next: number | null) => void;
  onEnded: () => void;
  onMediaError: (detail: string) => Promise<void>;
  onAutoplayBlocked: () => void;
}

const snapshotSchema = z.object({ media: playerMediaSchema, currentTime: z.number() });
const snapshotKey = (connectionId: string) => `abs-web:v1:player:${connectionId}`;
const REPORT_EVERY_MS = 15_000;
/** A gap longer than this between ticks is a suspended tab, not listening. */
const MAX_TICK_MS = 5_000;

function round(value: number) {
  return Math.round(value * 100) / 100;
}

export const usePlayerStore = create<PlayerStore>()((set, get) => {
  /** Changes whenever what the player should hold is decided anew, so a session opened for an older decision is let go. */
  let generation = 0;

  const persist = () => {
    const { player, connectionId } = get();
    if (!connectionId) return;
    if (player.phase === "active") {
      writeStored(snapshotKey(connectionId), { media: player.media, currentTime: round(player.currentTime) });
    } else {
      removeStored(snapshotKey(connectionId));
    }
  };

  const report = (force: boolean) => {
    const { listening, player, connectionId } = get();
    if (!listening || !connectionId || player.phase !== "active") return;
    const now = Date.now();
    if (!force && now - listening.lastReportedAt < REPORT_EVERY_MS) return;
    if (listening.timeListening <= 0 && !force) return;
    const next = createListeningReport(
      listening.identity,
      {
        currentTime: round(player.currentTime),
        timeListening: listening.timeListening,
        localNow: now,
        serverOffset: listening.serverOffset,
      },
      listening.last ?? undefined,
    );
    if (listening.timeListening > 0) outboxFor(connectionId).record(next);
    set({ listening: { ...listening, last: next, lastReportedAt: now } });
    persist();
  };

  const tick = (playing: boolean) => {
    const { listening } = get();
    if (!listening) return;
    const now = Date.now();
    const delta = listening.lastTick === null ? 0 : Math.min(now - listening.lastTick, MAX_TICK_MS);
    set({
      listening: {
        ...listening,
        timeListening: listening.timeListening + delta / 1000,
        lastTick: playing ? now : null,
      },
    });
  };

  const update = (
    change: (player: Extract<Player, { phase: "active" }>) => Partial<Extract<Player, { phase: "active" }>>,
  ) => {
    const { player } = get();
    if (player.phase !== "active") return;
    set({ player: { ...player, ...change(player) } });
  };

  const start = async (media: PlayerMedia, requestedTime: number | undefined, recovery = false) => {
    const { client, player: previous } = get();
    if (!client) return;
    // The server still has the old place while its discard is pending; this device already starts over.
    const startTime =
      requestedTime ??
      (outboxFor(client.connection.id).isHeld(media.itemId, media.episodeId) ? 0 : undefined);
    const preparing = ++generation;
    if (previous.phase === "active" && previous.source) {
      report(true);
      void closePlayback(client, previous.source.serverSessionId);
    }
    set({
      player: {
        phase: "active",
        media,
        source: null,
        status: "loading",
        error: null,
        currentTime: startTime ?? 0,
        seekTo: { time: startTime ?? 0 },
      },
      sleep: { kind: "off" },
      pausedAt: null,
    });
    try {
      const opened = await openPlayback(client, media.itemId, media.episodeId);
      const current = get().player;
      if (preparing !== generation || current.phase !== "active") {
        void closePlayback(client, opened.session.id);
        return;
      }
      const currentTime = startTime ?? opened.session.currentTime;
      const startedAt = Date.now() + opened.serverOffset;
      set({
        player: {
          ...current,
          media: {
            ...media,
            duration: opened.session.duration || media.duration,
            chapters: opened.session.chapters.length ? opened.session.chapters : media.chapters,
          },
          source: { serverSessionId: opened.session.id, tracks: opened.tracks, recovery },
          status: "playing",
          currentTime,
          seekTo: { time: currentTime },
        },
        listening: {
          identity: {
            id: randomId(),
            libraryItemId: media.itemId,
            episodeId: media.episodeId,
            libraryId: media.libraryId,
            mediaType: media.mediaType,
            displayTitle: media.title,
            displayAuthor: media.author,
            duration: opened.session.duration || media.duration,
            startTime: currentTime,
            startedAt,
            progressGeneration: opened.session.progressGeneration,
          },
          timeListening: 0,
          serverOffset: opened.serverOffset,
          lastTick: null,
          lastReportedAt: Date.now(),
          last: null,
        },
      });
      persist();
    } catch (error) {
      if (preparing !== generation) return;
      update(() => ({
        status: "paused",
        error: "start-failed",
        errorDetail: error instanceof AbsError ? error.message : String(error),
      }));
    }
  };

  return {
    player: { phase: "idle" },
    sleep: { kind: "off" },
    connectionId: null,
    client: null,
    listening: null,
    pausedAt: null,
    attach: (client) => {
      if (get().connectionId === client.connection.id) {
        set({ client });
        return;
      }
      generation++;
      const snapshot = readStored(snapshotKey(client.connection.id), snapshotSchema);
      set({
        client,
        connectionId: client.connection.id,
        listening: null,
        sleep: { kind: "off" },
        player: snapshot
          ? {
              phase: "active",
              media: snapshot.media,
              source: null,
              status: "paused",
              error: null,
              currentTime: snapshot.currentTime,
              seekTo: { time: snapshot.currentTime },
            }
          : { phase: "idle" },
      });
    },
    detach: () => {
      const { player, client } = get();
      report(true);
      if (player.phase === "active" && player.source && client)
        void closePlayback(client, player.source.serverSessionId);
      generation++;
      set({ player: { phase: "idle" }, client: null, connectionId: null, listening: null });
    },
    play: async ({ media, startTime }) => {
      const { player } = get();
      const same =
        player.phase === "active" &&
        player.media.itemId === media.itemId &&
        player.media.episodeId === media.episodeId;
      if (same && startTime === undefined) return get().resume();
      if (same && player.source && startTime !== undefined) {
        get().seek(startTime);
        return get().resume();
      }
      await start(media, startTime);
    },
    resume: async () => {
      const { player } = get();
      if (player.phase !== "active") return;
      if (!player.source) return start(player.media, player.currentTime);
      const { pausedAt } = get();
      set({ pausedAt: null });
      const rewind = pausedAt === null ? 0 : resumeRewind(Date.now() - pausedAt);
      if (
        rewind > 0 &&
        player.status === "paused" &&
        !useSettingsStore.getState().settings.disableAutoRewind
      ) {
        const chapter = player.media.chapters[chapterIndexAt(player.media.chapters, player.currentTime)];
        get().seek(Math.max(chapter?.start ?? 0, player.currentTime - rewind));
      }
      update(() => ({ status: "playing", error: null }));
    },
    pause: () => {
      if (get().player.phase === "active") set({ pausedAt: Date.now() });
      update(() => ({ status: "paused" }));
    },
    seek: (time) => {
      set({ pausedAt: null });
      update((player) => {
        const target = Math.max(0, Math.min(time, player.media.duration));
        return { currentTime: target, seekTo: { time: target } };
      });
      const { sleep, player } = get();
      if (sleep.kind === "chapter-end" && player.phase === "active") {
        const chapter = player.media.chapters[chapterIndexAt(player.media.chapters, player.currentTime)];
        set({ sleep: chapter ? { kind: "chapter-end", at: chapter.end } : { kind: "off" } });
      }
      report(true);
    },
    jump: (seconds) => {
      const { player } = get();
      if (player.phase === "active") get().seek(player.currentTime + seconds);
    },
    stop: async () => {
      const { player, client } = get();
      report(true);
      generation++;
      if (player.phase === "active" && player.source && client)
        await closePlayback(client, player.source.serverSessionId);
      set({ player: { phase: "idle" }, listening: null, sleep: { kind: "off" } });
      persist();
    },
    startOver: async ({ connectionId, itemId, episodeId }) => {
      outboxFor(connectionId).forget(itemId, episodeId);
      const isTarget = (media: PlayerMedia) => media.itemId === itemId && media.episodeId === episodeId;
      const { player, client } = get();
      if (get().connectionId !== connectionId) {
        // Another account is in the player; only the discarding account's saved place changes.
        const saved = readStored(snapshotKey(connectionId), snapshotSchema);
        if (saved && isTarget(saved.media))
          writeStored(snapshotKey(connectionId), { ...saved, currentTime: 0 });
        return;
      }
      if (player.phase !== "active" || !isTarget(player.media)) return;
      // This device changes before the server is told, so a slow close cannot overwrite whatever happens meanwhile.
      generation++;
      set({
        player: { ...player, source: null, status: "paused", currentTime: 0, seekTo: { time: 0 } },
        listening: null,
        pausedAt: null,
      });
      persist();
      // Closed without a final report, so the server is not told the old position again.
      if (player.source && client) await closePlayback(client, player.source.serverSessionId);
    },
    setSleep: (sleep) => set({ sleep }),
    checkpoint: () => {
      const { player } = get();
      tick(player.phase === "active" && player.status === "playing");
      report(true);
    },
    onTime: (time) => {
      const { player, sleep } = get();
      // Without a source the element still holds the previous file, whose time no longer applies.
      if (player.phase !== "active" || !player.source) return;
      tick(player.status === "playing");
      set({ player: { ...player, currentTime: time } });
      if (sleep.kind === "chapter-end" && time >= sleep.at - 0.3) {
        set({ sleep: { kind: "off" } });
        get().pause();
      }
      report(false);
    },
    onPlaying: () => {
      const { listening } = get();
      if (listening) set({ listening: { ...listening, lastTick: Date.now() } });
      update((player) => ({
        status: "playing",
        error: null,
        source: player.source?.recovery ? { ...player.source, recovery: false } : player.source,
      }));
    },
    onPaused: () => {
      tick(false);
      if (get().player.phase === "active") set({ pausedAt: get().pausedAt ?? Date.now() });
      update((player) => (player.status === "loading" ? {} : { status: "paused" }));
      report(true);
    },
    onFileEnded: (next) => {
      if (next === null) return get().onEnded();
      const { sleep } = get();
      // Time is reported only every quarter second or so, so a chapter ending with its file may never be seen ending.
      const stop = sleep.kind === "chapter-end" && next >= sleep.at - 0.3;
      if (stop) set({ sleep: { kind: "off" } });
      get().seek(next);
      if (stop) get().pause();
      else void get().resume();
    },
    onEnded: () => {
      tick(false);
      update((player) => ({ status: "paused", currentTime: player.media.duration }));
      report(true);
    },
    onMediaError: async (detail) => {
      const { player } = get();
      if (player.phase !== "active") return;
      // A fresh session renews expired media authorization; failed retries stop until audio actually plays.
      if (player.source && !player.source.recovery) {
        await start(player.media, player.currentTime, true);
        const after = get().player;
        if (after.phase === "active" && after.error === null) return;
      }
      update(() => ({ status: "paused", error: "media-failed", errorDetail: detail }));
    },
    onAutoplayBlocked: () => update(() => ({ status: "paused", error: "autoplay-blocked" })),
  };
});

export function isPlaying(player: Player, media: Pick<PlayerMedia, "itemId" | "episodeId">) {
  return (
    player.phase === "active" &&
    player.status === "playing" &&
    player.media.itemId === media.itemId &&
    player.media.episodeId === media.episodeId
  );
}

export function usePlayer() {
  return usePlayerStore((state) => state.player);
}
