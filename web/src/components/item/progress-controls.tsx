"use client";

import { CheckCircle2, RotateCcw, Undo2 } from "lucide-react";
import { useState } from "react";
import { InlineError } from "@/components/app/inline-error";
import { ProgressBar } from "@/components/media/cover";
import { Button } from "@/components/ui/button";
import { ConfirmDialog } from "@/components/ui/dialog";
import { useI18n } from "@/i18n/i18n";
import { formatClock } from "@/lib/abs/media";
import { useDiscardProgress, useSetFinished } from "@/lib/abs/mutations";
import type { MediaProgress } from "@/lib/abs/schemas";

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
  const [confirming, setConfirming] = useState(false);
  const finished = progress?.isFinished ?? false;
  const error = setFinished.error ?? discard.error;

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
            {t("WebDiscardProgress")}
          </Button>
        ) : null}
      </div>
      <InlineError error={error} />
      <ConfirmDialog
        open={confirming}
        title={t("WebDiscardProgress")}
        body={t("WebConfirm")}
        confirmLabel={t("WebDiscardProgress")}
        cancelLabel={t("WebCancel")}
        busy={discard.isPending}
        onClose={() => setConfirming(false)}
        onConfirm={() => {
          if (progress) discard.mutate(progress.id, { onSettled: () => setConfirming(false) });
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
