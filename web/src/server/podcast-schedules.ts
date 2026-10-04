import "server-only";
import { z } from "zod";
import { type Account, DomainError, findAccount, permissions } from "./accounts";
import { itemFor, itemsFor, librariesFor } from "./catalog";
import { catalogChanged, database, transaction } from "./data";
import { podcastSettings } from "./podcast-settings";
import { enqueue, episodesInput, readFeed, removeEpisode } from "./podcasts";
export function allSchedules(actor: Account) {
  return librariesFor(actor).flatMap((library) =>
    itemsFor(actor, library.id)
      .filter((item) => item.mediaType === "podcast")
      .map((item) => ({
        id: item.id,
        title: item.media.metadata.title,
        autoDownloadEpisodes: Boolean(item.media.autoDownloadEpisodes),
        ...scheduleFor(actor, item.id),
      })),
  );
}
export function updateSchedule(actor: Account, itemId: string, autoDownloadEpisodes: boolean) {
  const item = itemFor(actor, itemId);
  if (!permissions.parse(JSON.parse(actor.permissions)).update)
    throw new DomainError(403, "Update permission required");
  if (item.mediaType !== "podcast") throw new DomainError(400, "Not a podcast");
  transaction((db) => {
    item.media.autoDownloadEpisodes = autoDownloadEpisodes;
    item.updatedAt = Date.now();
    delete item.episodeDownloadsQueued;
    delete item.episodesDownloading;
    db.prepare("UPDATE catalog_items SET content=? WHERE id=?").run(JSON.stringify(item), itemId);
  });
  subscribe(actor, itemId);
  catalogChanged();
  return { success: true };
}
export function scheduleFor(actor: Account, itemId: string) {
  itemFor(actor, itemId);
  const row = database()
    .prepare(
      "SELECT next_check,lease_until,last_checked,last_error FROM podcast_subscriptions WHERE item_id=?",
    )
    .get(itemId);
  return {
    nextCheckAt: row?.next_check ?? null,
    leaseUntil: row?.lease_until ?? null,
    lastCheckedAt: row?.last_checked ?? null,
    lastError: row?.last_error ?? null,
  };
}
export function subscribe(actor: Account, itemId: string) {
  transaction((db) =>
    db
      .prepare(
        "INSERT INTO podcast_subscriptions VALUES(?,?,?,NULL,NULL,NULL) ON CONFLICT(item_id) DO NOTHING",
      )
      .run(itemId, actor.id, Date.now() + podcastSettings().updateIntervalMinutes * 60000),
  );
}
export async function checkPodcast(actor: Account, itemId: string) {
  const initial = itemFor(actor, itemId);
  if (!permissions.parse(JSON.parse(actor.permissions)).update)
    throw new DomainError(403, "Update permission required");
  if (initial.mediaType !== "podcast" || !initial.media.metadata.feedUrl)
    throw new DomainError(400, "A podcast feed URL is required");
  subscribe(actor, itemId);
  transaction((db) => {
    const claimed = db
      .prepare(
        "UPDATE podcast_subscriptions SET lease_until=? WHERE item_id=? AND (lease_until IS NULL OR lease_until<?)",
      )
      .run(Date.now() + 60000, itemId, Date.now());
    if (!claimed.changes) throw new DomainError(409, "Feed update already running");
  });
  try {
    const feed = await readFeed(initial.media.metadata.feedUrl);
    const currentActor = findAccount(actor.id),
      item = itemFor(currentActor, itemId);
    if (!permissions.parse(JSON.parse(currentActor.permissions)).update)
      throw new DomainError(403, "Update permission required");
    if (item.media.metadata.feedUrl !== initial.media.metadata.feedUrl)
      throw new DomainError(409, "Subscription changed during update");
    const settings = podcastSettings();
    if (item.media.autoDownloadEpisodes) {
      const offered = feed.podcast.episodes
        .filter((e) => e.enclosure?.url)
        .sort((a, b) => (b.publishedAt ?? 0) - (a.publishedAt ?? 0));
      const selected = settings.retentionEpisodes ? offered.slice(0, settings.retentionEpisodes) : offered;
      const pending = selected.filter(
        (e) =>
          !database()
            .prepare(
              "SELECT id FROM podcast_jobs WHERE item_id=? AND json_extract(content,'$.enclosure.url')=?",
            )
            .get(itemId, e.enclosure?.url ?? "") &&
          !item.media.episodes?.some((old) => old.enclosure?.url === e.enclosure?.url),
      );
      if (pending.length)
        enqueue(currentActor, itemId, episodesInput.parse(pending.slice(0, settings.maxQueue)));
    }
    database()
      .prepare(
        "UPDATE podcast_subscriptions SET lease_until=NULL,next_check=?,last_checked=?,last_error=NULL WHERE item_id=?",
      )
      .run(Date.now() + settings.updateIntervalMinutes * 60000, Date.now(), itemId);
    return scheduleFor(currentActor, itemId);
  } catch (error) {
    database()
      .prepare("UPDATE podcast_subscriptions SET lease_until=NULL,next_check=?,last_error=? WHERE item_id=?")
      .run(
        Date.now() + podcastSettings().updateIntervalMinutes * 60000,
        error instanceof DomainError ? error.message : "Feed update failed",
        itemId,
      );
    throw error;
  }
}
declare global {
  var leafwakePodcastSchedules: { running: boolean; timer: ReturnType<typeof setInterval> } | undefined;
}
export function startPodcastSchedules() {
  if (globalThis.leafwakePodcastSchedules) return;
  database().exec("UPDATE podcast_subscriptions SET lease_until=NULL");
  enrollExistingPodcasts();
  const timer = setInterval(() => {
    void scheduled().catch(() => {});
  }, 1000);
  timer.unref();
  globalThis.leafwakePodcastSchedules = { running: false, timer };
}
function enrollExistingPodcasts() {
  const root = database().prepare("SELECT id FROM users WHERE type='root' AND active=1 LIMIT 1").get();
  if (!root) return;
  database()
    .prepare(
      "INSERT OR IGNORE INTO podcast_subscriptions(item_id,user_id,next_check) SELECT id,?,? FROM catalog_items WHERE json_extract(content,'$.mediaType')='podcast' AND length(json_extract(content,'$.media.metadata.feedUrl'))>0",
    )
    .run(z.string().parse(root.id), Date.now() + podcastSettings().updateIntervalMinutes * 60000);
}
async function scheduled() {
  const worker = globalThis.leafwakePodcastSchedules;
  if (!worker || worker.running) return;
  worker.running = true;
  try {
    enrollExistingPodcasts();
    const rows = database()
      .prepare(
        "SELECT item_id,user_id FROM podcast_subscriptions WHERE next_check<=? AND (lease_until IS NULL OR lease_until<?) ORDER BY next_check LIMIT 2",
      )
      .all(Date.now(), Date.now());
    for (const row of rows) {
      try {
        await checkPodcast(findAccount(z.string().parse(row.user_id)), z.string().parse(row.item_id));
      } catch {
        database()
          .prepare(
            "UPDATE podcast_subscriptions SET next_check=?,last_error=COALESCE(last_error,'Subscription account is unavailable or lacks access') WHERE item_id=?",
          )
          .run(Date.now() + 60000, z.string().parse(row.item_id));
      }
    }
  } finally {
    worker.running = false;
  }
}
export async function retainEpisodes(actor: Account, itemId: string) {
  const keep = podcastSettings().retentionEpisodes;
  if (!keep) return;
  const item = itemFor(actor, itemId);
  const episodes = [...(item.media.episodes ?? [])].sort(
    (a, b) => (b.publishedAt ?? 0) - (a.publishedAt ?? 0) || b.id.localeCompare(a.id),
  );
  for (const episode of episodes.slice(keep)) await removeEpisode(findAccount(actor.id), itemId, episode.id);
}
