"use client";

import { CheckCircle2, RotateCcw, Undo2 } from "lucide-react";
import { useState, useSyncExternalStore } from "react";
import { InlineError } from "@/components/app/inline-error";
import { ProgressBar } from "@/components/media/cover";
import { Button } from "@/components/ui/button";
import { ConfirmDialog } from "@/components/ui/dialog";
import { useI18n } from "@/i18n/i18n";
import { formatClock } from "@/lib/abs/media";
import { useDiscardAnyway, useDiscardProgress, useKeepProgress, useSetFinished } from "@/lib/abs/mutations";
import type { MediaProgress } from "@/lib/abs/schemas";
import { outboxFor } from "@/lib/progress/sync";
import { useAbs } from "@/lib/session/store";

/** Where this account's discard of the book or episode stands, while one is under way. */
function useDiscardState(itemId: string, episodeId: string | null) {
  const outbox = outboxFor(useAbs().connection.id);
  return useSyncExternalStore(
    outbox.subscribe,
    () => outbox.discardState(itemId, episodeId),
    () => null,
  );
}

export function ProgressControls({
  itemId,
  episodeId,
  progress,
}: {
  itemId: string;
  episodeId?: string | null;
  progress: MediaProgress | undefined;
}) {
  const { t } = useI18n();
  const setFinished = useSetFinished();
  const discard = useDiscardProgress();
  const keep = useKeepProgress();
  const discardAnyway = useDiscardAnyway();
  const [confirming, setConfirming] = useState(false);
  const target = { itemId, episodeId: episodeId ?? null };
  const discardState = useDiscardState(target.itemId, target.episodeId);
  const finished = progress?.isFinished ?? false;
  const error = setFinished.error ?? discard.error ?? keep.error ?? discardAnyway.error;

  return (
    <div className="flex flex-col gap-2">
      <div className="flex flex-wrap gap-2">
        <Button
          size="sm"
          disabled={setFinished.isPending}
          onClick={() => setFinished.mutate({ itemId, episodeId, finished: !finished })}
        >
          {finished ? (
            <Undo2 aria-hidden className="size-4" />
          ) : (
            <CheckCircle2 aria-hidden className="size-4" />
          )}
          {finished ? t("WebMarkNotFinished") : t("WebMarkFinished")}
        </Button>
        {progress ? (
          <Button size="sm" variant="danger" onClick={() => setConfirming(true)}>
            <RotateCcw aria-hidden className="size-4" />
            {t("MessageDiscardProgress")}
          </Button>
        ) : null}
      </div>
      {discardState === "pending" ? (
        <p role="status" className="text-sm text-muted">
          {t("WebDiscardPending")}
        </p>
      ) : null}
      {discardState === "unconfirmed" ? (
        <div className="flex flex-col gap-2">
          <p role="status" className="text-sm text-muted">
            {t("WebDiscardUnconfirmed")}
          </p>
          <div className="flex flex-wrap gap-2">
            <Button size="sm" disabled={keep.isPending} onClick={() => keep.mutate(target)}>
              {t("WebKeepProgress")}
            </Button>
            <Button
              size="sm"
              variant="danger"
              disabled={discardAnyway.isPending}
              onClick={() => discardAnyway.mutate(target)}
            >
              {t("WebDiscardAnyway")}
            </Button>
          </div>
        </div>
      ) : null}
      <InlineError error={error} />
      <ConfirmDialog
        open={confirming}
        title={t("MessageDiscardProgress")}
        body={t("MessageConfirmDiscardProgress")}
        confirmLabel={t("MessageDiscardProgress")}
        cancelLabel={t("ButtonCancel")}
        busy={discard.isPending}
        onClose={() => setConfirming(false)}
        onConfirm={() => {
          if (progress)
            discard.mutate(
              { progressId: progress.id, itemId, episodeId: episodeId ?? null },
              { onSettled: () => setConfirming(false) },
            );
        }}
      />
    </div>
  );
}

/** Time left in the media, or null when nothing has been played or it is finished. */
export function remainingTime(progress: MediaProgress | undefined, duration: number) {
  return progress && !progress.isFinished && progress.currentTime > 0
    ? duration - progress.currentTime
    : null;
}

export function ProgressSummary({
  progress,
  duration,
}: {
  progress: MediaProgress | undefined;
  duration: number;
}) {
  const { t, locale } = useI18n();
  if (!progress || (progress.progress <= 0 && !progress.isFinished)) return null;
  return (
    <div className="flex max-w-md flex-col gap-1">
      <ProgressBar value={progress.isFinished ? 1 : progress.progress} label={t("LabelYourProgress")} />
      <p className="text-xs text-muted">
        {progress.isFinished
          ? t("LabelFinished")
          : `${Math.round(progress.progress * 100).toLocaleString(locale)}% · ${formatClock(remainingTime(progress, duration) ?? 0)}`}
      </p>
    </div>
  );
}
