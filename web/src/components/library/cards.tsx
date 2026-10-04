"use client";

import {
  BookOpen,
  CheckCircle2,
  ExternalLink,
  FolderPlus,
  Info,
  ListPlus,
  type LucideIcon,
  Play,
  Undo2,
} from "lucide-react";
import { useRouter } from "next/navigation";
import { useState } from "react";
import { InlineError } from "@/components/app/inline-error";
import { playerMediaFor } from "@/components/item/play-media";
import { AddToCollectionDialog, AddToPlaylistDialog } from "@/components/lists/add-to-list";
import { type CardLayout, MediaCard } from "@/components/media/item-card";
import type { MenuAction } from "@/components/ui/menu";
import { useI18n } from "@/i18n/i18n";
import { authorImageUrl, authorLine, type CoverShape, coverUrl, formatDuration } from "@/lib/abs/media";
import { useSetFinished } from "@/lib/abs/mutations";
import { can } from "@/lib/abs/permissions";
import { useEpisodeProgress, useItemProgress, useMe } from "@/lib/abs/queries";
import type { Author, LibraryItem, MediaProgress, Series } from "@/lib/abs/schemas";
import { usePlayerStore } from "@/lib/player/store";
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
        href={`/library/${item.libraryId}/series/${encodeURIComponent(collapsed.id)}`}
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
  return <PlayableCard item={item} shape={shape} layout={layout} progress={progress} />;
}

/** A book, or a podcast's latest episode, with its own menu of what its details page offers. */
function PlayableCard({
  item,
  shape,
  layout,
  progress,
}: {
  item: LibraryItem;
  shape: CoverShape;
  layout?: CardLayout;
  progress: MediaProgress | undefined;
}) {
  const { t } = useI18n();
  const { client } = useAbs();
  const router = useRouter();
  const me = useMe().data;
  const setFinished = useSetFinished();
  const [adding, setAdding] = useState<"playlist" | "collection" | null>(null);
  const episode = item.recentEpisode;
  const isBook = item.mediaType === "book";
  const href = episode ? `/item/${item.id}/episode/${episode.id}` : `/item/${item.id}`;
  const title = episode ? episode.title : item.media.metadata.title;
  const playable = episode
    ? !!episode.audioFile
    : (item.media.numTracks ?? item.media.tracks?.length ?? 0) > 0;
  const finished = progress?.isFinished ?? false;
  const started = !!progress && !finished && progress.currentTime > 0;
  const run = (
    key: string,
    label: string,
    icon: LucideIcon,
    onSelect: () => void,
    disabled = false,
  ): MenuAction => ({ kind: "run", key, label, icon, onSelect, disabled });
  const actions: MenuAction[] = [
    ...(playable
      ? [
          run("play", started ? t("WebResume") : t("ButtonPlay"), Play, () =>
            usePlayerStore.getState().play({ media: playerMediaFor(client, item, episode ?? undefined) }),
          ),
        ]
      : []),
    ...(isBook && item.media.ebookFile
      ? [run("read", t("ButtonRead"), BookOpen, () => router.push(`/read/${item.id}`))]
      : []),
    run("details", t("HeaderDetails"), Info, () => router.push(href)),
    { kind: "new-tab", key: "tab", label: t("WebOpenInNewTab"), icon: ExternalLink, href },
    ...(isBook || episode
      ? [run("playlist", t("LabelAddToPlaylist"), ListPlus, () => setAdding("playlist"))]
      : []),
    ...(isBook && can(me, "update")
      ? [run("collection", t("WebAddToCollection"), FolderPlus, () => setAdding("collection"))]
      : []),
    ...(isBook || episode
      ? [
          run(
            "finished",
            finished ? t("WebMarkNotFinished") : t("WebMarkFinished"),
            finished ? Undo2 : CheckCircle2,
            () =>
              setFinished.mutate({
                itemId: item.id,
                episodeId: episode?.id ?? null,
                finished: !finished,
                progressGeneration: item.progressGenerations?.[episode?.id ?? ""] ?? item.progressGeneration,
              }),
            setFinished.isPending,
          ),
        ]
      : []),
  ];
  const numEpisodes = item.media.numEpisodes;
  return (
    <>
      <MediaCard
        href={href}
        menu={{ label: t("WebItemActions", title), actions }}
        title={title}
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
      <InlineError error={setFinished.error} />
      {adding === "playlist" ? (
        <AddToPlaylistDialog
          libraryId={item.libraryId}
          entry={{ libraryItemId: item.id, episodeId: episode?.id ?? null }}
          onClose={() => setAdding(null)}
        />
      ) : null}
      {adding === "collection" ? (
        <AddToCollectionDialog libraryId={item.libraryId} itemId={item.id} onClose={() => setAdding(null)} />
      ) : null}
    </>
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
      href={`/library/${libraryId}/series/${encodeURIComponent(series.id)}`}
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
      href={`/library/${libraryId}/authors/${encodeURIComponent(author.id)}`}
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
