"use client";

import { type CardLayout, MediaCard } from "@/components/media/item-card";
import { useI18n } from "@/i18n/i18n";
import { authorImageUrl, authorLine, type CoverShape, coverUrl, formatDuration } from "@/lib/abs/media";
import { useEpisodeProgress, useItemProgress } from "@/lib/abs/queries";
import type { Author, LibraryItem, Series } from "@/lib/abs/schemas";
import { useAbs } from "@/lib/session/store";

export function ItemCard({
  item,
  shape,
  layout,
}: {
  item: LibraryItem;
  shape: CoverShape;
  layout?: CardLayout;
}) {
  const { t } = useI18n();
  const { client } = useAbs();
  const episode = item.recentEpisode;
  const bookProgress = useItemProgress().data?.get(item.id);
  const episodeProgress = useEpisodeProgress(item.id).data?.get(episode?.id ?? "");
  const progress = episode ? episodeProgress : bookProgress;
  const collapsed = item.collapsedSeries;
  if (collapsed) {
    return (
      <MediaCard
        href={`/library/${item.libraryId}/series/${collapsed.id}`}
        title={collapsed.name}
        subtitle={t("WebItemsCount", collapsed.numBooks)}
        cover={coverUrl(client, item)}
        shape={shape}
        badge={String(collapsed.numBooks)}
        progressLabel={t("LabelProgress")}
        finishedLabel={t("LabelFinished")}
        missingCoverLabel={t("WebNoCover")}
        layout={layout}
      />
    );
  }
  const numEpisodes = item.media.numEpisodes;
  return (
    <MediaCard
      href={episode ? `/item/${item.id}/episode/${episode.id}` : `/item/${item.id}`}
      title={episode ? episode.title : item.media.metadata.title}
      subtitle={episode ? item.media.metadata.title : authorLine(item)}
      detail={
        item.mediaType === "podcast"
          ? numEpisodes
            ? t("WebEpisodesCount", numEpisodes)
            : undefined
          : formatDuration(item.media.duration) || undefined
      }
      layout={layout}
      cover={coverUrl(client, item)}
      shape={shape}
      badge={
        item.mediaType === "podcast" && !episode && item.numEpisodesIncomplete
          ? String(item.numEpisodesIncomplete)
          : undefined
      }
      progress={
        progress
          ? {
              value:
                progress.ebookProgress && !progress.duration ? progress.ebookProgress : progress.progress,
              finished: progress.isFinished,
            }
          : undefined
      }
      progressLabel={t("LabelProgress")}
      finishedLabel={t("LabelFinished")}
      missingCoverLabel={t("WebNoCover")}
    />
  );
}

export function SeriesCard({
  series,
  libraryId,
  shape,
}: {
  series: Series;
  libraryId: string;
  shape: CoverShape;
}) {
  const { t } = useI18n();
  const { client } = useAbs();
  const first = series.books[0];
  return (
    <MediaCard
      href={`/library/${libraryId}/series/${series.id}`}
      title={series.name}
      subtitle={t("WebItemsCount", series.books.length)}
      cover={first ? coverUrl(client, first) : null}
      shape={shape}
      badge={String(series.books.length)}
      progressLabel={t("LabelProgress")}
      finishedLabel={t("LabelFinished")}
      missingCoverLabel={t("WebNoCover")}
    />
  );
}

export function AuthorCard({ author, libraryId }: { author: Author; libraryId: string }) {
  const { t } = useI18n();
  const { client } = useAbs();
  return (
    <MediaCard
      href={`/library/${libraryId}/authors/${author.id}`}
      title={author.name}
      subtitle={author.numBooks ? t("WebItemsCount", author.numBooks) : undefined}
      cover={authorImageUrl(client, author)}
      shape="square"
      progressLabel={t("LabelProgress")}
      finishedLabel={t("LabelFinished")}
      missingCoverLabel={t("WebNoCover")}
    />
  );
}
