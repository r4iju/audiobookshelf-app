"use client";

import type Hls from "hls.js";
import { useEffect, useRef } from "react";
import { type PlayerTrack, usePlayer, usePlayerStore } from "@/lib/player/store";
import { locate } from "@/lib/player/timeline";
import { useAbs } from "@/lib/session/store";
import { useSettings } from "@/lib/settings/store";

const FADE_SECONDS = 10;

export function AudioEngine() {
  const audioRef = useRef<HTMLAudioElement>(null);
  const loaded = useRef<{ sessionId: string; index: number; track: PlayerTrack } | null>(null);
  const hlsRef = useRef<Hls | null>(null);
  const switching = useRef(false);
  const { client } = useAbs();
  const player = usePlayer();
  const sleep = usePlayerStore((state) => state.sleep);
  const settings = useSettings();
  const active = player.phase === "active" ? player : null;
  const source = active?.source ?? null;
  const status = active?.status ?? "paused";
  const seekTo = active?.seekTo ?? null;
  const media = active?.media ?? null;

  // External system: the player store holds this connection's client and restores the last player after a reload.
  useEffect(() => {
    usePlayerStore.getState().attach(client);
  }, [client]);
  useEffect(() => () => usePlayerStore.getState().detach(), []);

  // External system: the audio element (and hls.js for transcoded streams) loads the file under the position.
  useEffect(() => {
    const audio = audioRef.current;
    if (!audio || !source || !seekTo) return;
    const { index, offset } = locate(source.tracks, seekTo.time);
    const track = source.tracks[index];
    if (!track) return;
    const current = loaded.current;
    if (current && current.sessionId === source.serverSessionId && current.index === index) {
      audio.currentTime = offset;
      return;
    }
    switching.current = true;
    hlsRef.current?.destroy();
    hlsRef.current = null;
    loaded.current = { sessionId: source.serverSessionId, index, track };
    const seekWhenReady = () => {
      audio.currentTime = offset;
      switching.current = false;
    };
    audio.addEventListener("loadedmetadata", seekWhenReady, { once: true });
    if (track.hls && !audio.canPlayType("application/vnd.apple.mpegurl")) {
      void import("hls.js").then(({ default: HlsPlayer }) => {
        if (loaded.current?.track !== track) return;
        const hls = new HlsPlayer({
          // Read at request time so segments use whatever token the client holds after a refresh.
          xhrSetup: (xhr) => {
            const bearer = usePlayerStore.getState().client?.bearer;
            if (bearer) xhr.setRequestHeader("Authorization", `Bearer ${bearer}`);
          },
          startPosition: offset,
        });
        hls.on(HlsPlayer.Events.ERROR, (_event, data) => {
          if (data.fatal) void usePlayerStore.getState().onMediaError(data.details);
        });
        hls.loadSource(track.url);
        hls.attachMedia(audio);
        hlsRef.current = hls;
      });
    } else {
      audio.src = track.url;
      audio.load();
    }
    // A new file starts paused; keep playing when the store says so.
    const state = usePlayerStore.getState().player;
    if (state.phase === "active" && state.status === "playing") audio.play().catch(() => {});
  }, [source, seekTo]);

  // External system: play and pause the audio element to match the requested status.
  useEffect(() => {
    const audio = audioRef.current;
    if (!audio || !source) return;
    if (status === "playing" && audio.paused) {
      audio.play().catch((error: unknown) => {
        if (error instanceof DOMException && error.name === "NotAllowedError")
          usePlayerStore.getState().onAutoplayBlocked();
      });
    } else if (status === "paused" && !audio.paused) {
      audio.pause();
    }
  }, [status, source]);

  // External system: playback speed of the audio element.
  useEffect(() => {
    const audio = audioRef.current;
    if (!audio) return;
    audio.playbackRate = settings.playbackRate;
    audio.defaultPlaybackRate = settings.playbackRate;
  }, [settings.playbackRate]);

  // External system: a wall-clock sleep timer that fades the audio element out before pausing it.
  useEffect(() => {
    const audio = audioRef.current;
    if (!audio) return;
    if (sleep.kind !== "until") {
      audio.volume = 1;
      return;
    }
    const timer = setInterval(() => {
      const remaining = (sleep.endsAt - Date.now()) / 1000;
      if (remaining <= 0) {
        audio.volume = 1;
        usePlayerStore.getState().setSleep({ kind: "off" });
        usePlayerStore.getState().pause();
      } else if (!settings.disableSleepTimerFadeOut && remaining < FADE_SECONDS) {
        audio.volume = Math.max(0.05, remaining / FADE_SECONDS);
      }
    }, 250);
    return () => {
      clearInterval(timer);
      audio.volume = 1;
    };
  }, [sleep, settings.disableSleepTimerFadeOut]);

  // External system: the operating system's media controls (lock screen, keyboard media keys, headsets).
  useEffect(() => {
    if (!("mediaSession" in navigator) || !media) return;
    navigator.mediaSession.metadata = new MediaMetadata({
      title: media.title,
      artist: media.author,
      artwork: media.coverUrl ? [{ src: media.coverUrl }] : [],
    });
    const store = usePlayerStore.getState;
    const handlers: Array<[MediaSessionAction, MediaSessionActionHandler]> = [
      ["play", () => void store().resume()],
      ["pause", () => store().pause()],
      ["seekbackward", (details) => store().jump(-(details.seekOffset ?? settings.jumpBackwardsTime))],
      ["seekforward", (details) => store().jump(details.seekOffset ?? settings.jumpForwardTime)],
      ["seekto", (details) => details.seekTime !== undefined && store().seek(details.seekTime)],
    ];
    for (const [action, handler] of handlers) {
      try {
        navigator.mediaSession.setActionHandler(action, handler);
      } catch {}
    }
    return () => {
      for (const [action] of handlers) {
        try {
          navigator.mediaSession.setActionHandler(action, null);
        } catch {}
      }
    };
  }, [media, settings.jumpBackwardsTime, settings.jumpForwardTime]);

  // External system: page lifecycle; listening so far is recorded before the tab is hidden or closed.
  useEffect(() => {
    const checkpoint = () => usePlayerStore.getState().checkpoint();
    const onVisibility = () => document.visibilityState === "hidden" && checkpoint();
    window.addEventListener("pagehide", checkpoint);
    document.addEventListener("visibilitychange", onVisibility);
    return () => {
      window.removeEventListener("pagehide", checkpoint);
      document.removeEventListener("visibilitychange", onVisibility);
    };
  }, []);

  // External system: hls.js instances are torn down with the engine.
  useEffect(() => () => hlsRef.current?.destroy(), []);

  const store = usePlayerStore.getState;
  return (
    // biome-ignore lint/a11y/useMediaCaption: spoken-word audio; the server provides no caption tracks
    <audio
      ref={audioRef}
      preload="auto"
      className="hidden"
      onTimeUpdate={(event) => {
        const track = loaded.current?.track;
        if (track && !switching.current) store().onTime(track.startOffset + event.currentTarget.currentTime);
      }}
      onPlaying={() => store().onPlaying()}
      onPause={() => {
        if (!switching.current) store().onPaused();
      }}
      onEnded={() => {
        const state = store().player;
        const current = loaded.current;
        if (state.phase !== "active" || !state.source || !current) return;
        const next = state.source.tracks[current.index + 1];
        // The element pauses at the end of each file; the book continues with the next one.
        if (next) {
          store().seek(next.startOffset);
          void store().resume();
        } else store().onEnded();
      }}
      onError={(event) => {
        const error = event.currentTarget.error;
        if (error && !hlsRef.current) void store().onMediaError(error.message || `code ${error.code}`);
      }}
    />
  );
}
