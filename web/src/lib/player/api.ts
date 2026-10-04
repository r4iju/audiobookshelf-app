import type { AbsClient } from "@/lib/abs/client";
import { playbackSessionSchema } from "@/lib/abs/schemas";
import { deviceInfo } from "@/lib/device";

const candidateMimeTypes = [
  "audio/flac",
  "audio/mpeg",
  "audio/mp4",
  "audio/ogg",
  "audio/aac",
  "audio/webm",
  "audio/x-m4a",
  "audio/x-m4b",
  "audio/wav",
];

/** What this browser can decode, so the server direct-plays whatever it can and transcodes the rest to HLS. */
export function supportedMimeTypes() {
  const probe = document.createElement("audio");
  return candidateMimeTypes.filter((type) => probe.canPlayType(type) !== "");
}

/**
 * Opens a server playback session only to obtain playable media URLs. Progress is reported separately as a local
 * session (see progress/outbox), so this session is never synced; the server discards sessions without listening time.
 */
export async function openPlayback(client: AbsClient, itemId: string, episodeId: string | null) {
  const requestedAt = Date.now();
  const session = await client.send(
    "POST",
    `/api/items/${itemId}/play${episodeId ? `/${episodeId}` : ""}`,
    {
      deviceInfo: deviceInfo(),
      mediaPlayer: "html5",
      forceDirectPlay: false,
      forceTranscode: false,
      supportedMimeTypes: supportedMimeTypes(),
    },
    playbackSessionSchema,
  );
  const receivedAt = Date.now();
  const serverOffset = session.updatedAt ? Math.round(session.updatedAt - (requestedAt + receivedAt) / 2) : 0;
  const tracks = session.audioTracks.map((track, position) => {
    const hls = track.contentUrl.includes("/hls/") || track.mimeType === "application/vnd.apple.mpegurl";
    return {
      // HTML media elements cannot attach headers. Each load uses credentials current after any refresh.
      get url() {
        const url = new URL(
          client.url(
            hls ? track.contentUrl : `/public/session/${session.id}/track/${track.index ?? position + 1}`,
          ),
        );
        url.searchParams.set("token", client.bearer);
        return url.toString();
      },
      startOffset: track.startOffset,
      duration: track.duration,
      hls,
    };
  });
  return { session, tracks, serverOffset };
}

export function closePlayback(client: AbsClient, sessionId: string) {
  return client.command("POST", `/api/session/${sessionId}/close`).catch(() => {});
}
