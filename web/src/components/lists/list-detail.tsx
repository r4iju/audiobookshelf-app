"use client";

import { Pause, Play, Trash2, X } from "lucide-react";
import { type ReactNode, useState } from "react";
import { InlineError } from "@/components/app/inline-error";
import { MediaRow } from "@/components/media/media-row";
import { Button } from "@/components/ui/button";
import { ConfirmDialog } from "@/components/ui/dialog";
import { EmptyState } from "@/components/ui/status";
import { useI18n } from "@/i18n/i18n";
import { type ListEntry, nextToPlay } from "@/lib/abs/lists";
import { formatDuration } from "@/lib/abs/media";
import { useMe } from "@/lib/abs/queries";
import { isPlaying, type PlayerMedia, usePlayer, usePlayerStore } from "@/lib/player/store";

export interface DetailEntry extends ListEntry {
  key: string;
  href: string;
  media: PlayerMedia;
}

/** A collection or playlist: its entries in server order, played from the first unfinished one. */
export function ListDetail({
  name,
  description,
  label,
  entries,
  remove,
  deletion,
  busy,
  error,
  editor,
}: {
  editor?: ReactNode;
  name: string;
  description?: string | null;
  label: string;
  entries: DetailEntry[];
  /** Omitted when this account may not remove entries. */
  remove?: { label: (title: string) => string; run: (entry: DetailEntry) => void };
  /** Omitted when this account may not delete the list. */
  deletion?: { label: string; run: () => void };
  busy: boolean;
  error: Error | null;
}) {
  const { t } = useI18n();
  const player = usePlayer();
  const progress = useMe().data?.mediaProgress ?? [];
  const [confirming, setConfirming] = useState(false);
  const next = nextToPlay(entries, progress);
  const playingHere = entries.some((entry) => isPlaying(player, entry.media));

  return (
    <div className="flex flex-col gap-6">
      <header className="flex flex-wrap items-end justify-between gap-4">
        <div className="flex min-w-0 flex-col gap-1">
          <h1 className="text-2xl font-bold tracking-tight break-words lg:text-3xl">{name}</h1>
          {description ? <p className="max-w-prose text-sm text-muted">{description}</p> : null}
          <p className="text-sm text-muted">{t("WebItemsCount", entries.length)}</p>
        </div>
        <div className="flex flex-wrap gap-2">
          <Button
            variant="primary"
            disabled={!playingHere && !next}
            onClick={() =>
              playingHere
                ? usePlayerStore.getState().pause()
                : next && void usePlayerStore.getState().play({ media: next.media })
            }
          >
            {playingHere ? <Pause aria-hidden className="size-4" /> : <Play aria-hidden className="size-4" />}
            {playingHere ? t("ButtonPause") : t("ButtonPlay")}
          </Button>
          {deletion ? (
            <Button variant="danger" onClick={() => setConfirming(true)}>
              <Trash2 aria-hidden className="size-4" />
              {deletion.label}
            </Button>
          ) : null}
        </div>
      </header>
      {editor}
      {!next && entries.length ? <p className="text-sm text-muted">{t("WebNothingToPlay")}</p> : null}
      <InlineError error={error} />

      {entries.length ? (
        <ul
          aria-label={label}
          className="divide-y divide-line overflow-hidden rounded-[var(--radius-card)] bg-surface"
        >
          {entries.map((entry) => {
            const playing = isPlaying(player, entry.media);
            return (
              <MediaRow
                key={entry.key}
                href={entry.href}
                cover={entry.media.coverUrl}
                title={entry.media.title}
                subtitle={entry.media.author}
                meta={formatDuration(entry.media.duration)}
                missingCoverLabel={t("WebNoCover")}
                actions={
                  <>
                    {entry.playable ? (
                      <Button
                        size="icon"
                        variant="ghost"
                        aria-label={
                          playing
                            ? t("WebPauseNamed", entry.media.title)
                            : t("WebPlayNamed", entry.media.title)
                        }
                        onClick={() =>
                          playing
                            ? usePlayerStore.getState().pause()
                            : void usePlayerStore.getState().play({ media: entry.media })
                        }
                      >
                        {playing ? (
                          <Pause aria-hidden className="size-5" />
                        ) : (
                          <Play aria-hidden className="size-5" />
                        )}
                      </Button>
                    ) : null}
                    {remove ? (
                      <Button
                        size="icon"
                        variant="ghost"
                        disabled={busy}
                        aria-label={remove.label(entry.media.title)}
                        onClick={() => remove.run(entry)}
                      >
                        <X aria-hidden className="size-5" />
                      </Button>
                    ) : null}
                  </>
                }
              />
            );
          })}
        </ul>
      ) : (
        <EmptyState title={t("MessageNoItems")} />
      )}

      {deletion ? (
        <ConfirmDialog
          open={confirming}
          title={deletion.label}
          body={t("WebConfirm")}
          confirmLabel={t("WebDelete")}
          cancelLabel={t("ButtonCancel")}
          busy={busy}
          onClose={() => setConfirming(false)}
          onConfirm={() => {
            setConfirming(false);
            deletion.run();
          }}
        />
      ) : null}
    </div>
  );
}
