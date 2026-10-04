import "server-only";
import { z } from "zod";
import { podcastSearchResultsSchema } from "@/lib/abs/schemas";
import { type Account, DomainError, requireAdministrator } from "./accounts";
import { database, transaction } from "./data";
import { remoteText, remoteUrl } from "./remote";
export const podcastSettingsSchema = z.object({
  discoveryEnabled: z.boolean(),
  providerUrl: z.string().max(4096),
  country: z.string().regex(/^[A-Z]{2}$/),
  updateIntervalMinutes: z.number().int().min(1).max(10080),
  maxQueue: z.number().int().min(1).max(128),
  maxConcurrent: z.number().int().min(1).max(2),
  maxEpisodeBytes: z.number().int().min(1048576).max(1073741824),
  downloadTimeoutSeconds: z.number().int().min(30).max(3600),
  retentionEpisodes: z.number().int().min(0).max(1000),
});
const defaults = {
  discoveryEnabled: true,
  providerUrl: "https://itunes.apple.com/search",
  country: "GB",
  updateIntervalMinutes: 60,
  maxQueue: 128,
  maxConcurrent: 2,
  maxEpisodeBytes: 1073741824,
  downloadTimeoutSeconds: 600,
  retentionEpisodes: 0,
};
export function podcastSettings() {
  const row = database().prepare("SELECT content FROM product_settings WHERE key='podcasts'").get();
  return podcastSettingsSchema.parse(row ? JSON.parse(z.string().parse(row.content)) : defaults);
}
export function savePodcastSettings(actor: Account, value: z.infer<typeof podcastSettingsSchema>) {
  requireAdministrator(actor);
  remoteUrl(value.providerUrl);
  transaction((db) =>
    db
      .prepare(
        "INSERT INTO product_settings VALUES('podcasts',?) ON CONFLICT(key) DO UPDATE SET content=excluded.content",
      )
      .run(JSON.stringify(value)),
  );
  return value;
}
const providerResult = z.object({
  collectionId: z.number().optional(),
  collectionName: z.string().max(4096),
  artistName: z.string().max(4096).optional(),
  feedUrl: z.string().max(4096),
  artworkUrl600: z.string().optional(),
  artworkUrl100: z.string().optional(),
  genres: z.array(z.string()).max(100).optional(),
  releaseDate: z.string().optional(),
  collectionViewUrl: z.string().optional(),
  artistId: z.number().optional(),
  collectionExplicitness: z.string().optional(),
});
const cache = new Map<string, { expires: number; value: z.infer<typeof podcastSearchResultsSchema> }>();
let requests: number[] = [];
export async function searchPodcasts(actor: Account, term: string) {
  if (!actor.active) throw new DomainError(401, "Sign-in required");
  const q = z.string().trim().min(1).max(256).parse(term),
    settings = podcastSettings();
  if (!settings.discoveryEnabled)
    throw new DomainError(503, "Podcast discovery is disabled. You can still subscribe by feed URL.");
  const url = remoteUrl(settings.providerUrl);
  url.searchParams.set("term", q);
  url.searchParams.set("media", "podcast");
  url.searchParams.set("entity", "podcast");
  url.searchParams.set("limit", "50");
  url.searchParams.set("country", settings.country);
  const key = url.toString(),
    prior = cache.get(key);
  if (prior && prior.expires > Date.now()) return prior.value;
  requests = requests.filter((time) => time > Date.now() - 60000);
  if (requests.length >= 10)
    throw new DomainError(429, "Podcast provider request limit reached; retry shortly");
  requests.push(Date.now());
  try {
    const response = z
      .object({ results: z.array(z.unknown()).max(200) })
      .parse(JSON.parse(await remoteText(key)));
    const results = response.results.slice(0, 50).flatMap((raw) => {
      const parsed = providerResult.safeParse(raw);
      if (!parsed.success) return [];
      const result = parsed.data;
      remoteUrl(result.feedUrl);
      return [
        {
          id: result.collectionId,
          title: result.collectionName,
          artistName: result.artistName,
          feedUrl: result.feedUrl,
          cover: result.artworkUrl600 ?? result.artworkUrl100,
          genres: result.genres ?? [],
          releaseDate: result.releaseDate,
          pageUrl: result.collectionViewUrl,
          artistId: result.artistId,
          explicit: result.collectionExplicitness === "explicit",
        },
      ];
    });
    const value = podcastSearchResultsSchema.parse(results);
    if (cache.size >= 128) {
      const first = cache.keys().next().value;
      if (first) cache.delete(first);
    }
    cache.set(key, { expires: Date.now() + 300000, value });
    return value;
  } catch {
    throw new DomainError(503, "Podcast discovery provider is unavailable. Retry or subscribe by feed URL.");
  }
}
