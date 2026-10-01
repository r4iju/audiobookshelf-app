import { z } from "zod";
import { create } from "zustand";
import { type AbsClient, AbsError } from "@/lib/abs/client";
import { chapterSchema } from "@/lib/abs/schemas";
import { createListeningReport, type ListeningReport, type ReportIdentity } from "@/lib/progress/outbox";
import { outboxFor } from "@/lib/progress/sync";
import { readStored, removeStored, writeStored } from "@/lib/storage/local";
import { closePlayback, openPlayback } from "./api";
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
  /** Opened to recover from a media failure; a second failure is reported instead of retried. */
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
  attach: (client: AbsClient) => void;
  detach: () => void;
  play: (request: PlayRequest) => Promise<void>;
  resume: () => Promise<void>;
  pause: () => void;
  seek: (time: number) => void;
  jump: (seconds: number) => void;
  stop: () => Promise<void>;
  setSleep: (sleep: Sleep) => void;
  /** Records listening so far, for example before the page is hidden or closed. */
  checkpoint: () => void;
  // Events from the audio element.
  onTime: (time: number) => void;
  onPlaying: () => void;
  onPaused: () => void;
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

  const start = async (media: PlayerMedia, startTime: number | undefined, recovery = false) => {
    const { client, player: previous } = get();
    if (!client) return;
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
    });
    try {
      const opened = await openPlayback(client, media.itemId, media.episodeId);
      const current = get().player;
      if (
        current.phase !== "active" ||
        current.media.itemId !== media.itemId ||
        current.media.episodeId !== media.episodeId
      ) {
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
            id: crypto.randomUUID(),
            libraryItemId: media.itemId,
            episodeId: media.episodeId,
            libraryId: media.libraryId,
            mediaType: media.mediaType,
            displayTitle: media.title,
            displayAuthor: media.author,
            duration: opened.session.duration || media.duration,
            startTime: currentTime,
            startedAt,
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
    attach: (client) => {
      if (get().connectionId === client.connection.id) {
        set({ client });
        return;
      }
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
      update(() => ({ status: "playing", error: null }));
    },
    pause: () => {
      update(() => ({ status: "paused" }));
    },
    seek: (time) => {
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
      if (player.phase === "active" && player.source && client)
        await closePlayback(client, player.source.serverSessionId);
      set({ player: { phase: "idle" }, listening: null, sleep: { kind: "off" } });
      persist();
    },
    setSleep: (sleep) => set({ sleep }),
    checkpoint: () => {
      const { player } = get();
      tick(player.phase === "active" && player.status === "playing");
      report(true);
    },
    onTime: (time) => {
      const { player, sleep } = get();
      if (player.phase !== "active") return;
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
      update(() => ({ status: "playing", error: null }));
    },
    onPaused: () => {
      tick(false);
      update((player) => (player.status === "loading" ? {} : { status: "paused" }));
      report(true);
    },
    onEnded: () => {
      tick(false);
      update((player) => ({ status: "paused", currentTime: player.media.duration }));
      report(true);
    },
    onMediaError: async (detail) => {
      const { player } = get();
      if (player.phase !== "active") return;
      // The server forgets playback sessions on restart; one fresh session at the same position recovers from that.
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
