"use client";

import { CheckCircle2, ListPlus, Loader2, Pause, Play, RefreshCw, Undo2, X } from "lucide-react";
import Link from "next/link";
import { useState } from "react";
import { InlineError } from "@/components/app/inline-error";
import { SortDirection } from "@/components/library/sort-direction";
import { AddToPlaylistDialog } from "@/components/lists/add-to-list";
import { ProgressBar } from "@/components/media/cover";
import { Button } from "@/components/ui/button";
import { ConfirmDialog, Dialog } from "@/components/ui/dialog";
import { Checkbox } from "@/components/ui/field";
import { QueryState } from "@/components/ui/query-state";
import { SelectField } from "@/components/ui/select";
import { EmptyState } from "@/components/ui/status";
import { useI18n } from "@/i18n/i18n";
import {
  episodeDuration,
  episodeFilters,
  episodeListState,
  episodeSorts,
  newFeedEpisodes,
  visibleEpisodes,
} from "@/lib/abs/episodes";
import { formatClock, formatDuration } from "@/lib/abs/media";
import {
  type PlaylistEntry,
  useClearDownloadQueue,
  useDownloadEpisodes,
  useSetFinished,
} from "@/lib/abs/mutations";
import { isAdmin } from "@/lib/abs/permissions";
import { useEpisodeProgress, useMe, usePodcastFeed } from "@/lib/abs/queries";
import type { LibraryItem, MediaProgress, PodcastEpisode } from "@/lib/abs/schemas";
import { isPlaying, usePlayer, usePlayerStore } from "@/lib/player/store";
import { useAbs } from "@/lib/session/store";
import { useSettings, useSettingsStore } from "@/lib/settings/store";
import { htmlToText } from "@/lib/text";
import { playerMediaFor } from "./play-media";

export function EpisodeList({ item }: { item: LibraryItem }) {
  const { t } = useI18n();
  const admin = isAdmin(useMe().data);
  const progressOf = useEpisodeProgress(item.id).data ?? new Map<string, MediaProgress>();
  const [dialog, setDialog] = useState<
    { kind: "playlist"; entry: PlaylistEntry } | { kind: "feed"; feedUrl: string } | null
  >(null);
  const state = episodeListState(useSettings(), item.media.metadata.type);
  const episodes = visibleEpisodes(item.media.episodes ?? [], progressOf, state);
  const feedUrl = item.media.metadata.feedUrl;
  const saveChoice = useSettingsStore((store) => store.update);

  return (
    <section aria-labelledby="episodes" className="flex flex-col gap-3">
      <div className="flex flex-wrap items-end justify-between gap-3">
        <h2 id="episodes" className="text-lg font-semibold">
          {t("HeaderEpisodes")}
        </h2>
        <div className="flex w-full flex-wrap items-end gap-3 sm:w-auto">
          <div className="flex w-full items-end gap-2 sm:w-auto">
            <SelectField
              label={t("WebSortBy")}
              value={state.sort}
              options={episodeSorts.map(([value, label]) => ({ value, label: t(label) }))}
              onChange={(value) => {
                const sort = episodeSorts.find(([key]) => key === value)?.[0];
                if (sort) saveChoice({ podcastEpisodesOrderBy: sort });
              }}
              className="min-w-0 flex-1 sm:w-44 sm:flex-none"
            />
            <SortDirection
              desc={state.desc}
              onChange={(desc) => saveChoice({ podcastEpisodesOrderDesc: desc })}
            />
          </div>
          <SelectField
            label={t("WebFilterBy")}
            value={state.filter}
            options={episodeFilters.map(([value, label]) => ({ value, label: t(label) }))}
            onChange={(value) => {
              const filter = episodeFilters.find(([key]) => key === value)?.[0];
              if (filter) saveChoice({ podcastEpisodesFilterBy: filter });
            }}
            className="w-full sm:w-44"
          />
          {admin && feedUrl ? (
            <Button onClick={() => setDialog({ kind: "feed", feedUrl })}>
              <RefreshCw aria-hidden className="size-4" />
              {t("WebFindNewEpisodes")}
            </Button>
          ) : null}
        </div>
      </div>

      <DownloadQueue item={item} admin={admin} />

      {episodes.length ? (
        <ul className="divide-y divide-line overflow-hidden rounded-[var(--radius-card)] bg-surface">
          {episodes.map((episode) => (
            <EpisodeRow
              key={episode.id}
              item={item}
              episode={episode}
              progress={progressOf.get(episode.id)}
              onAddToPlaylist={() =>
                setDialog({ kind: "playlist", entry: { libraryItemId: item.id, episodeId: episode.id } })
              }
            />
          ))}
        </ul>
      ) : (
        <EmptyState title={t("WebNoEpisodesMatch")} />
      )}

      {dialog?.kind === "playlist" ? (
        <AddToPlaylistDialog
          libraryId={item.libraryId}
          entry={dialog.entry}
          onClose={() => setDialog(null)}
        />
      ) : null}
      {dialog?.kind === "feed" ? (
        <FindEpisodesDialog item={item} feedUrl={dialog.feedUrl} onClose={() => setDialog(null)} />
      ) : null}
    </section>
  );
}

function EpisodeRow({
  item,
  episode,
  progress,
  onAddToPlaylist,
}: {
  item: LibraryItem;
  episode: PodcastEpisode;
  progress: MediaProgress | undefined;
  onAddToPlaylist: () => void;
}) {
  const { t, locale } = useI18n();
  const { client } = useAbs();
  const player = usePlayer();
  const setFinished = useSetFinished();
  const playing = isPlaying(player, { itemId: item.id, episodeId: episode.id });
  const finished = progress?.isFinished ?? false;
  const duration = episodeDuration(episode);
  const description = htmlToText(episode.subtitle ?? episode.description);

  return (
    <li className="flex flex-col gap-2 px-4 py-3 sm:flex-row sm:items-center sm:gap-4">
      <div className="flex min-w-0 flex-1 flex-col gap-1">
        <h3 className="font-medium break-words">
          <Link
            href={`/item/${item.id}/episode/${episode.id}`}
            className="rounded hover:underline focus-ring"
          >
            {episode.title}
          </Link>
        </h3>
        <p className="flex flex-wrap gap-x-3 text-xs text-muted">
          {episode.publishedAt ? (
            <span>{new Date(episode.publishedAt).toLocaleDateString(locale)}</span>
          ) : null}
          {episode.season ? <span>{`${t("LabelSeason")} ${episode.season}`}</span> : null}
          {episode.episode ? <span>{`${t("LabelEpisode")} ${episode.episode}`}</span> : null}
          {duration ? <span>{formatDuration(duration)}</span> : null}
          {finished ? <span className="text-success">{t("LabelFinished")}</span> : null}
          {progress && !finished ? (
            <span>{formatClock(Math.max(0, duration - progress.currentTime))}</span>
          ) : null}
        </p>
        {progress && !finished && progress.progress > 0 ? (
          <div className="max-w-xs">
            <ProgressBar value={progress.progress} label={t("LabelProgress")} />
          </div>
        ) : null}
        {description ? <p className="line-clamp-2 text-sm text-muted">{description}</p> : null}
        <InlineError error={setFinished.error} />
      </div>
      <div className="flex shrink-0 items-center gap-1">
        <Button
          size="icon"
          variant="primary"
          aria-label={playing ? t("WebPauseNamed", episode.title) : t("WebPlayNamed", episode.title)}
          onClick={() =>
            playing
              ? usePlayerStore.getState().pause()
              : void usePlayerStore.getState().play({ media: playerMediaFor(client, item, episode) })
          }
        >
          {playing ? <Pause aria-hidden className="size-5" /> : <Play aria-hidden className="size-5" />}
        </Button>
        <Button
          size="icon"
          variant="ghost"
          disabled={setFinished.isPending}
          aria-label={
            finished ? t("WebMarkNamedNotFinished", episode.title) : t("WebMarkNamedFinished", episode.title)
          }
          onClick={() => setFinished.mutate({ itemId: item.id, episodeId: episode.id, finished: !finished })}
        >
          {finished ? (
            <Undo2 aria-hidden className="size-5" />
          ) : (
            <CheckCircle2 aria-hidden className="size-5" />
          )}
        </Button>
        <Button
          size="icon"
          variant="ghost"
          aria-label={t("WebAddNamedToPlaylist", episode.title)}
          onClick={onAddToPlaylist}
        >
          <ListPlus aria-hidden className="size-5" />
        </Button>
      </div>
    </li>
  );
}

/** The server's own download queue for this podcast, kept current by its socket events. */
function DownloadQueue({ item, admin }: { item: LibraryItem; admin: boolean }) {
  const { t } = useI18n();
  const clear = useClearDownloadQueue();
  const [confirming, setConfirming] = useState(false);
  const downloading = item.episodesDownloading ?? [];
  const queued = item.episodeDownloadsQueued ?? [];
  if (!downloading.length && !queued.length) return null;

  return (
    <>
      <div
        role="status"
        className="flex flex-col gap-2 rounded-xl border border-line bg-surface-2 px-4 py-3 text-sm"
      >
        {downloading.map((download) => (
          <p key={download.id} className="flex items-center gap-2">
            <Loader2 aria-hidden className="size-4 shrink-0 animate-spin" />
            {download.episodeDisplayTitle
              ? `${t("MessageDownloadingEpisode")} "${download.episodeDisplayTitle}"`
              : t("MessageDownloadingEpisode")}
          </p>
        ))}
        {queued.length ? (
          <div className="flex flex-wrap items-center justify-between gap-2">
            <p>{t("MessageEpisodesQueuedForDownload", queued.length)}</p>
            {admin ? (
              <Button
                size="sm"
                variant="ghost"
                disabled={clear.isPending}
                onClick={() => setConfirming(true)}
              >
                <X aria-hidden className="size-4" />
                {t("WebClearDownloadQueue")}
              </Button>
            ) : null}
          </div>
        ) : null}
        <InlineError error={clear.error} />
      </div>
      <ConfirmDialog
        open={confirming}
        title={t("HeaderConfirm")}
        body={t("MessageConfirmDeleteEpisodeDownloadQueue")}
        confirmLabel={t("WebClearDownloadQueue")}
        cancelLabel={t("ButtonCancel")}
        busy={clear.isPending}
        onClose={() => setConfirming(false)}
        onConfirm={() => clear.mutate(item.id, { onSettled: () => setConfirming(false) })}
      />
    </>
  );
}

/** Lists the podcast's feed (read by the server) and queues the chosen episodes for download on the server. */
function FindEpisodesDialog({
  item,
  feedUrl,
  onClose,
}: {
  item: LibraryItem;
  feedUrl: string;
  onClose: () => void;
}) {
  const { t, locale } = useI18n();
  const feed = usePodcastFeed(feedUrl);
  const download = useDownloadEpisodes();
  const [selected, setSelected] = useState(0);

  return (
    <Dialog open onClose={onClose} title={t("HeaderEpisodes")}>
      <QueryState query={feed}>
        {(data) => {
          const offered = newFeedEpisodes(data.podcast.episodes, item.media.episodes ?? []);
          if (!offered.length) return <EmptyState title={t("WebNoFeedEpisodes")} />;
          return (
            <form
              className="flex flex-col gap-3"
              onChange={(event) => setSelected(new FormData(event.currentTarget).getAll("episode").length)}
              action={(form) => {
                const episodes = form.getAll("episode").flatMap((value) => {
                  const choice = offered[Number(value)];
                  return choice ? [choice.episode] : [];
                });
                if (episodes.length) download.mutate({ itemId: item.id, episodes }, { onSuccess: onClose });
              }}
            >
              <ul className="flex max-h-80 flex-col gap-1 overflow-y-auto">
                {offered.map(({ episode, downloaded }, index) => (
                  <li key={episode.enclosure?.url ?? index}>
                    <label className="flex cursor-pointer items-start gap-3 rounded-xl px-2 py-2 hover:bg-surface-2 has-disabled:cursor-not-allowed has-disabled:opacity-60">
                      <Checkbox
                        name="episode"
                        value={index}
                        disabled={downloaded || !episode.enclosure}
                        defaultChecked={false}
                        className="mt-0.5"
                      />
                      <span className="flex min-w-0 flex-col">
                        <span className="text-sm font-medium break-words">{episode.title}</span>
                        <span className="text-xs text-muted">
                          {episode.publishedAt
                            ? new Date(episode.publishedAt).toLocaleDateString(locale)
                            : null}
                          {downloaded ? ` · ${t("WebAlreadyOnServer")}` : null}
                        </span>
                      </span>
                    </label>
                  </li>
                ))}
              </ul>
              <InlineError error={download.error} />
              <div className="flex justify-end gap-2">
                <Button variant="ghost" onClick={onClose}>
                  {t("ButtonCancel")}
                </Button>
                <Button type="submit" variant="primary" disabled={!selected || download.isPending}>
                  {t("WebDownloadEpisodes", selected)}
                </Button>
              </div>
            </form>
          );
        }}
      </QueryState>
    </Dialog>
  );
}
