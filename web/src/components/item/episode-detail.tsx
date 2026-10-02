"use client";

import { ListPlus, Pause, Play, Trash2 } from "lucide-react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { useState } from "react";
import { InlineError } from "@/components/app/inline-error";
import { useLibrary } from "@/components/library/use-library";
import { AddToPlaylistDialog } from "@/components/lists/add-to-list";
import { Cover } from "@/components/media/cover";
import { Button } from "@/components/ui/button";
import { ConfirmDialog } from "@/components/ui/dialog";
import { QueryState } from "@/components/ui/query-state";
import { Alert } from "@/components/ui/status";
import { useI18n } from "@/i18n/i18n";
import { episodeDuration } from "@/lib/abs/episodes";
import { coverUrl, formatClock, formatDuration } from "@/lib/abs/media";
import { useRemoveEpisode } from "@/lib/abs/mutations";
import { can, isAdmin } from "@/lib/abs/permissions";
import { useEpisodeProgress, useItem, useMe } from "@/lib/abs/queries";
import type { LibraryItem, PodcastEpisode } from "@/lib/abs/schemas";
import { isPlaying, usePlayer, usePlayerStore } from "@/lib/player/store";
import { useAbs } from "@/lib/session/store";
import { htmlToText } from "@/lib/text";
import { playerMediaFor } from "./play-media";
import { ProgressControls, ProgressSummary, remainingTime } from "./progress-controls";

export function EpisodeDetail({ itemId, episodeId }: { itemId: string; episodeId: string }) {
  const { t } = useI18n();
  const item = useItem(itemId);
  return (
    <QueryState query={item}>
      {(data) => {
        const episode = data.media.episodes?.find((entry) => entry.id === episodeId);
        return episode ? <EpisodeView item={data} episode={episode} /> : <Alert>{t("WebNotFound")}</Alert>;
      }}
    </QueryState>
  );
}

function EpisodeView({ item, episode }: { item: LibraryItem; episode: PodcastEpisode }) {
  const { t, locale } = useI18n();
  const { client } = useAbs();
  const router = useRouter();
  const { shape } = useLibrary(item.libraryId);
  const me = useMe().data;
  const progress = useEpisodeProgress(item.id).data?.get(episode.id);
  const player = usePlayer();
  const remove = useRemoveEpisode(({ itemId, episodeId }) => {
    // Only from the removed episode's page: the user may have gone elsewhere while the server answered.
    if (window.location.pathname.endsWith(`/item/${itemId}/episode/${episodeId}`))
      router.replace(`/item/${itemId}`);
  });
  const [dialog, setDialog] = useState<"playlist" | "remove" | null>(null);
  const playing = isPlaying(player, { itemId: item.id, episodeId: episode.id });
  const duration = episodeDuration(episode);
  const remaining = remainingTime(progress, duration);
  const description = htmlToText(episode.description ?? episode.subtitle);
  const podcastTitle = item.media.metadata.title;
  // The server requires delete permission; the legacy client offers removal to administrators only.
  const canRemove = isAdmin(me) && can(me, "delete");

  return (
    <article className="flex flex-col gap-8">
      <div className="flex flex-col gap-6 md:flex-row md:items-start">
        <div className="w-36 shrink-0 self-center md:w-48 md:self-start">
          <Cover
            src={coverUrl(client, item)}
            title={podcastTitle}
            shape={shape}
            missingLabel={t("WebNoCover")}
          />
        </div>
        <div className="flex min-w-0 flex-1 flex-col gap-4">
          <header className="flex flex-col gap-1">
            <Link
              href={`/item/${item.id}`}
              className="self-start rounded text-sm font-medium text-accent hover:underline focus-ring"
            >
              {podcastTitle}
            </Link>
            <h1 className="text-2xl font-bold tracking-tight break-words lg:text-3xl">{episode.title}</h1>
            <p className="flex flex-wrap gap-x-3 text-sm text-muted">
              {episode.publishedAt ? (
                <span>{new Date(episode.publishedAt).toLocaleDateString(locale)}</span>
              ) : null}
              {duration ? <span>{formatDuration(duration)}</span> : null}
            </p>
          </header>

          {episode.episode || episode.season || episode.episodeType ? (
            <ul className="flex flex-wrap gap-2 text-xs">
              {episode.episode ? (
                <li className="rounded-full bg-surface-2 px-2.5 py-1">{`${t("LabelEpisode")} #${episode.episode}`}</li>
              ) : null}
              {episode.season ? (
                <li className="rounded-full bg-surface-2 px-2.5 py-1">{`${t("LabelSeason")} #${episode.season}`}</li>
              ) : null}
              {episode.episodeType ? (
                <li className="rounded-full bg-surface-2 px-2.5 py-1 capitalize">{episode.episodeType}</li>
              ) : null}
            </ul>
          ) : null}

          <ProgressSummary progress={progress} duration={duration} />
          <ProgressControls itemId={item.id} episodeId={episode.id} progress={progress} />

          <div className="flex flex-wrap gap-3">
            <Button
              variant="primary"
              onClick={() =>
                playing
                  ? usePlayerStore.getState().pause()
                  : void usePlayerStore.getState().play({ media: playerMediaFor(client, item, episode) })
              }
            >
              {playing ? <Pause aria-hidden className="size-4" /> : <Play aria-hidden className="size-4" />}
              {playing ? t("ButtonPause") : t("ButtonPlay")}
              {!playing && remaining !== null ? (
                <span className="font-normal opacity-80">{formatClock(remaining)}</span>
              ) : null}
            </Button>
            <Button onClick={() => setDialog("playlist")}>
              <ListPlus aria-hidden className="size-4" />
              {t("LabelAddToPlaylist")}
            </Button>
            {canRemove ? (
              <Button variant="danger" onClick={() => setDialog("remove")}>
                <Trash2 aria-hidden className="size-4" />
                {t("ButtonRemoveFromServer")}
              </Button>
            ) : null}
          </div>
          <InlineError error={remove.error} />
        </div>
      </div>

      {description ? (
        <section aria-labelledby="episode-description" className="flex max-w-prose flex-col gap-2">
          <h2 id="episode-description" className="text-lg font-semibold">
            {t("LabelDescription")}
          </h2>
          <p className="whitespace-pre-line text-sm leading-relaxed">{description}</p>
        </section>
      ) : null}

      {dialog === "playlist" ? (
        <AddToPlaylistDialog
          libraryId={item.libraryId}
          entry={{ libraryItemId: item.id, episodeId: episode.id }}
          onClose={() => setDialog(null)}
        />
      ) : null}
      <ConfirmDialog
        open={dialog === "remove"}
        title={t("HeaderConfirm")}
        body={t("MessageConfirmDeleteServerEpisode", episode.title)}
        confirmLabel={t("ButtonRemoveFromServer")}
        cancelLabel={t("ButtonCancel")}
        busy={remove.isPending}
        onClose={() => setDialog(null)}
        onConfirm={() =>
          remove.mutate({ itemId: item.id, episodeId: episode.id }, { onSettled: () => setDialog(null) })
        }
      />
    </article>
  );
}
