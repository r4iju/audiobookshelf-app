import { expect, it, vi } from "vitest";
import { createAbsClient } from "@/lib/abs/client";
import { openPlayback } from "./api";

vi.mock("@/lib/device", () => ({ deviceInfo: () => ({ deviceId: "browser-qa" }) }));

it("authorizes direct audio element requests using the refreshed playback credentials", async () => {
  vi.stubGlobal("document", { createElement: () => ({ canPlayType: () => "probably" }) });
  let valid = "renewed/+";
  const client = createAbsClient({
    connection: {
      id: "c1",
      serverUrl: "https://leafwake.example",
      username: "qa",
      userId: "u1",
      auth: { kind: "token", accessToken: "expired", refreshToken: "refresh" },
    },
    saveAuth: () => {},
    fetcher: async (input, init) => {
      const request = new Request(input, init);
      if (request.url.endsWith("/auth/refresh"))
        return Response.json({
          user: { id: "u1", username: "qa", accessToken: valid, refreshToken: "next" },
        });
      if (request.headers.get("authorization") !== `Bearer ${valid}`)
        return new Response(null, { status: 401 });
      return Response.json({
        id: "s1",
        libraryItemId: "i1",
        mediaType: "book",
        duration: 30,
        currentTime: 0,
        playMethod: 0,
        audioTracks: [
          {
            index: 1,
            startOffset: 0,
            duration: 30,
            contentUrl: "/api/items/i1/file/f1",
            mimeType: "audio/mpeg",
          },
        ],
      });
    },
  });
  try {
    const { tracks } = await openPlayback(client, "i1", null);
    const track = tracks[0];
    if (!track) throw new Error("Playback returned no audio track");
    const media = new URL(track.url);
    expect(media.pathname).toBe("/public/session/s1/track/1");
    expect(media.searchParams.get("token")).toBe("renewed/+");
    for (const next of ["second", "third"]) {
      valid = next;
      await client.command("GET", "/api/me");
      expect(new URL(track.url).searchParams.get("token")).toBe(next);
    }
  } finally {
    vi.unstubAllGlobals();
  }
});
