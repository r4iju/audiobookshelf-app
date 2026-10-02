"use client";

import { Pause, Play } from "lucide-react";
import { usePathname } from "next/navigation";
import { episodeCoverUrl, playerMediaForEpisode } from "@/components/item/play-media";
import { MediaRow } from "@/components/media/media-row";
import { Button } from "@/components/ui/button";
import { QueryState } from "@/components/ui/query-state";
import { EmptyState } from "@/components/ui/status";
import { useI18n } from "@/i18n/i18n";
import { episodeDuration } from "@/lib/abs/episodes";
import { formatDuration } from "@/lib/abs/media";
import { PAGE_SIZE, useRecentEpisodes } from "@/lib/abs/queries";
import { isPlaying, usePlayer, usePlayerStore } from "@/lib/player/store";
import { useAbs } from "@/lib/session/store";
import { Pager } from "./pager";
import { useLibrary } from "./use-library";

export function LatestEpisodes({ libraryId, page }: { libraryId: string; page: number }) {
  const { t, locale } = useI18n();
  const { client } = useAbs();
  const pathname = usePathname();
  const player = usePlayer();
  useLibrary(libraryId);
  const recent = useRecentEpisodes(libraryId, page);
  // The server does not report a total; a full page means there may be another.
  const pages = recent.data?.episodes.length === PAGE_SIZE ? page + 1 : page;

  return (
    <div className="flex flex-col gap-6">
      <h1 className="text-2xl font-bold tracking-tight lg:text-3xl">{t("WebLatestEpisodes")}</h1>
      <QueryState query={recent}>
        {(data) =>
          data.episodes.length === 0 ? (
            <EmptyState title={t("MessageNoItems")} />
          ) : (
            <ul
              aria-label={t("WebLatestEpisodes")}
              className="divide-y divide-line overflow-hidden rounded-[var(--radius-card)] bg-surface"
            >
              {data.episodes.map((episode) => {
                const playing = isPlaying(player, { itemId: episode.libraryItemId, episodeId: episode.id });
                return (
                  <MediaRow
                    key={episode.id}
                    href={`/item/${episode.libraryItemId}`}
                    cover={episodeCoverUrl(client, episode)}
                    title={episode.title}
                    subtitle={episode.podcast?.metadata.title ?? undefined}
                    meta={[
                      episode.publishedAt ? new Date(episode.publishedAt).toLocaleDateString(locale) : null,
                      formatDuration(episodeDuration(episode)),
                    ]
                      .filter(Boolean)
                      .join(" · ")}
                    missingCoverLabel={t("WebNoCover")}
                    actions={
                      <Button
                        size="icon"
                        variant="primary"
                        aria-label={
                          playing ? t("WebPauseNamed", episode.title) : t("WebPlayNamed", episode.title)
                        }
                        onClick={() =>
                          playing
                            ? usePlayerStore.getState().pause()
                            : void usePlayerStore
                                .getState()
                                .play({ media: playerMediaForEpisode(client, episode) })
                        }
                      >
                        {playing ? (
                          <Pause aria-hidden className="size-5" />
                        ) : (
                          <Play aria-hidden className="size-5" />
                        )}
                      </Button>
                    }
                  />
                );
              })}
            </ul>
          )
        }
      </QueryState>
      <Pager
        page={page}
        pages={pages}
        hrefFor={(next) => (next > 1 ? `${pathname}?page=${next}` : pathname)}
        pageLabel={t("WebPage", page)}
      />
    </div>
  );
}
