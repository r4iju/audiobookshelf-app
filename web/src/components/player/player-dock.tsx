"use client";

import {
  Bookmark,
  ChevronDown,
  ChevronUp,
  Loader2,
  Pause,
  Play,
  RotateCcw,
  RotateCw,
  SkipBack,
  SkipForward,
  X,
} from "lucide-react";
import Link from "next/link";
import { useId, useState } from "react";
import { Cover } from "@/components/media/cover";
import { Button } from "@/components/ui/button";
import { Alert } from "@/components/ui/status";
import { type Translate, useI18n } from "@/i18n/i18n";
import { formatClock } from "@/lib/abs/media";
import { useCreateBookmark } from "@/lib/abs/mutations";
import { type Player, type Sleep, usePlayer, usePlayerStore } from "@/lib/player/store";
import { chapterIndexAt, nextChapterStart, previousChapterStart } from "@/lib/player/timeline";
import { ratePresets, sleepPresetsMinutes, useSettings, useSettingsStore } from "@/lib/settings/store";
import { useProgressSync } from "./progress-sync";

type Active = Extract<Player, { phase: "active" }>;

function errorText(t: Translate, player: Active) {
  switch (player.error) {
    case "autoplay-blocked":
      return t("WebAutoplayBlocked");
    case "media-failed":
      return t("WebPlaybackFailed", player.errorDetail ?? t("WebMediaUnavailable"));
    case "start-failed":
      return t("WebPlaybackFailed", player.errorDetail ?? t("WebErrorGeneric"));
    case null:
      return null;
  }
}

function sleepValue(sleep: Sleep) {
  return sleep.kind === "off" ? "off" : sleep.kind === "chapter-end" ? "chapter" : "running";
}

export function PlayerDock() {
  const player = usePlayer();
  const pending = useProgressSync();
  const { t } = useI18n();
  if (player.phase !== "active") {
    return pending > 0 ? (
      <p
        role="status"
        className="fixed right-4 bottom-20 z-30 rounded-full bg-surface-2 px-3 py-1 text-xs lg:bottom-4"
      >
        {t("WebPendingProgress", pending)}
      </p>
    ) : null;
  }
  return <Dock player={player} pending={pending} />;
}

function Dock({ player, pending }: { player: Active; pending: number }) {
  const { t } = useI18n();
  const settings = useSettings();
  const updateSettings = useSettingsStore((state) => state.update);
  const sleep = usePlayerStore((state) => state.sleep);
  const actions = usePlayerStore.getState;
  const createBookmark = useCreateBookmark();
  const [expanded, setExpanded] = useState(false);
  const ids = useId();
  const { media, currentTime, status } = player;
  const chapters = media.chapters;
  const chapterIndex = chapterIndexAt(chapters, currentTime);
  const chapter = chapters[chapterIndex];
  const range =
    settings.useChapterTrack && chapter
      ? { min: chapter.start, max: chapter.end }
      : { min: 0, max: media.duration };
  const speed = settings.playbackRate;
  const scale = settings.scaleElapsedTimeBySpeed ? speed : 1;
  const elapsed = (currentTime - range.min) / scale;
  const remaining = (range.max - currentTime) / scale;
  const error = errorText(t, player);
  const rateOptions = (ratePresets as readonly number[]).includes(speed)
    ? ratePresets
    : [...ratePresets, speed].sort((a, b) => a - b);
  const sleepRemaining =
    sleep.kind === "until" ? Math.max(0, Math.round((sleep.endsAt - Date.now()) / 1000)) : 0;

  return (
    <section
      aria-label={t("WebPlayer")}
      className="fixed inset-x-0 bottom-[calc(3.5rem+env(safe-area-inset-bottom))] z-40 border-t border-line bg-surface/95 shadow-[0_-8px_24px_rgb(0_0_0/0.25)] backdrop-blur lg:bottom-0 lg:left-60"
    >
      <div className="mx-auto flex max-w-6xl flex-col gap-2 px-4 py-3 lg:px-6">
        {error ? <Alert>{error}</Alert> : null}
        <div className="flex items-center gap-3">
          <Link href={`/item/${media.itemId}`} className="w-12 shrink-0 rounded-lg focus-ring">
            <Cover
              src={media.coverUrl}
              title={media.title}
              shape="square"
              missingLabel={t("WebNoCover")}
              className="rounded-lg"
            />
          </Link>
          <div className="min-w-0 flex-1">
            <p className="truncate text-sm font-semibold">{media.title}</p>
            <p className="truncate text-xs text-muted">
              {chapter
                ? `${chapter.title} · ${t("WebChapterOf", chapterIndex + 1, chapters.length)}`
                : media.author}
            </p>
          </div>
          <div className="flex items-center gap-1">
            <Button
              size="icon"
              variant="ghost"
              className="max-sm:hidden"
              aria-label={t("WebPreviousChapter")}
              disabled={!chapters.length}
              onClick={() => actions().seek(previousChapterStart(chapters, currentTime))}
            >
              <SkipBack aria-hidden className="size-5 rtl:rotate-180" />
            </Button>
            <Button
              size="icon"
              variant="ghost"
              aria-label={t("WebJumpBack", `${settings.jumpBackwardsTime} s`)}
              onClick={() => actions().jump(-settings.jumpBackwardsTime)}
            >
              <RotateCcw aria-hidden className="size-5" />
            </Button>
            <Button
              size="icon"
              variant="primary"
              aria-label={status === "playing" ? t("ButtonPause") : t("ButtonPlay")}
              onClick={() => (status === "playing" ? actions().pause() : void actions().resume())}
            >
              {status === "loading" ? (
                <Loader2 aria-hidden className="size-5 animate-spin" />
              ) : status === "playing" ? (
                <Pause aria-hidden className="size-5" />
              ) : (
                <Play aria-hidden className="size-5" />
              )}
            </Button>
            <Button
              size="icon"
              variant="ghost"
              aria-label={t("WebJumpForward", `${settings.jumpForwardTime} s`)}
              onClick={() => actions().jump(settings.jumpForwardTime)}
            >
              <RotateCw aria-hidden className="size-5" />
            </Button>
            <Button
              size="icon"
              variant="ghost"
              className="max-sm:hidden"
              aria-label={t("WebNextChapter")}
              disabled={nextChapterStart(chapters, currentTime) === null}
              onClick={() => {
                const next = nextChapterStart(chapters, currentTime);
                if (next !== null) actions().seek(next);
              }}
            >
              <SkipForward aria-hidden className="size-5 rtl:rotate-180" />
            </Button>
          </div>
          <Button
            size="icon"
            variant="ghost"
            aria-expanded={expanded}
            aria-label={expanded ? t("WebCollapsePlayer") : t("WebExpandPlayer")}
            onClick={() => setExpanded(!expanded)}
          >
            {expanded ? (
              <ChevronDown aria-hidden className="size-5" />
            ) : (
              <ChevronUp aria-hidden className="size-5" />
            )}
          </Button>
        </div>

        <div className="flex items-center gap-3 text-xs text-muted tabular-nums">
          <span className="w-14 text-end">
            <span className="sr-only">{t("WebElapsed")} </span>
            {formatClock(elapsed)}
          </span>
          <input
            type="range"
            aria-label={t("WebSeek")}
            aria-valuetext={`${formatClock(currentTime)} / ${formatClock(media.duration)}`}
            min={range.min}
            max={range.max}
            step={1}
            value={Math.min(range.max, Math.max(range.min, currentTime))}
            onChange={(event) => actions().seek(Number(event.target.value))}
            className="h-1.5 flex-1 cursor-pointer accent-[var(--accent-strong)]"
          />
          <span className="w-14">
            <span className="sr-only">{t("WebRemaining")} </span>-{formatClock(remaining)}
          </span>
        </div>

        {pending > 0 ? (
          <p role="status" className="text-xs text-muted">
            {t("WebPendingProgress", pending)}
          </p>
        ) : null}

        <div className={`${expanded ? "flex" : "hidden lg:flex"} flex-wrap items-end gap-3`}>
          <div className="flex flex-col gap-1 text-xs font-medium">
            <label htmlFor={`${ids}-speed`}>{t("LabelPlaybackSpeed")}</label>
            <select
              id={`${ids}-speed`}
              value={String(speed)}
              onChange={(event) => updateSettings({ playbackRate: Number(event.target.value) })}
              className="min-h-9 rounded-lg border border-line bg-surface px-2 text-sm focus-ring"
            >
              {rateOptions.map((rate) => (
                <option key={rate} value={String(rate)}>
                  {rate}×
                </option>
              ))}
            </select>
          </div>
          <div className="flex gap-1">
            <Button
              size="sm"
              aria-label={t("WebSlower")}
              disabled={speed <= 0.5}
              onClick={() => updateSettings({ playbackRate: Math.round((speed - 0.1) * 10) / 10 })}
            >
              −
            </Button>
            <Button
              size="sm"
              aria-label={t("WebFaster")}
              disabled={speed >= 10}
              onClick={() => updateSettings({ playbackRate: Math.round((speed + 0.1) * 10) / 10 })}
            >
              +
            </Button>
          </div>
          <div className="flex flex-col gap-1 text-xs font-medium">
            <label htmlFor={`${ids}-sleep`}>{t("LabelSleepTimer")}</label>
            <select
              id={`${ids}-sleep`}
              value={sleepValue(sleep)}
              onChange={(event) => {
                const value = event.target.value;
                if (value === "off") actions().setSleep({ kind: "off" });
                else if (value === "chapter" && chapter)
                  actions().setSleep({ kind: "chapter-end", at: chapter.end });
                else if (value !== "running")
                  actions().setSleep({ kind: "until", endsAt: Date.now() + Number(value) * 60_000 });
              }}
              className="min-h-9 rounded-lg border border-line bg-surface px-2 text-sm focus-ring"
            >
              <option value="off">{t("LabelOff")}</option>
              {sleep.kind === "until" ? (
                <option value="running">{t("WebSleepTimerActive", formatClock(sleepRemaining))}</option>
              ) : null}
              {sleepPresetsMinutes.map((minutes) => (
                <option key={minutes} value={String(minutes)}>
                  {minutes} min
                </option>
              ))}
              {chapters.length ? <option value="chapter">{t("LabelEndOfChapter")}</option> : null}
            </select>
          </div>
          {sleep.kind === "until" ? (
            <div className="flex gap-1">
              <Button
                size="sm"
                onClick={() =>
                  actions().setSleep({ kind: "until", endsAt: Math.max(Date.now(), sleep.endsAt - 300_000) })
                }
              >
                {t("WebRemoveMinutes", 5)}
              </Button>
              <Button
                size="sm"
                onClick={() => actions().setSleep({ kind: "until", endsAt: sleep.endsAt + 300_000 })}
              >
                {t("WebAddMinutes", 5)}
              </Button>
            </div>
          ) : null}
          <Button
            size="sm"
            disabled={createBookmark.isPending}
            onClick={() =>
              createBookmark.mutate({
                itemId: media.itemId,
                time: currentTime,
                title: chapter
                  ? `${chapter.title} ${formatClock(currentTime - chapter.start)}`
                  : formatClock(currentTime),
              })
            }
          >
            <Bookmark aria-hidden className="size-4" />
            {t("ButtonCreateBookmark")}
          </Button>
          {createBookmark.isSuccess ? (
            <span role="status" className="text-xs text-muted">
              {t("WebBookmarkAdded")}
            </span>
          ) : null}
          {createBookmark.isError ? (
            <span role="alert" className="text-xs text-danger">
              {t("ToastBookmarkCreateFailed")}
            </span>
          ) : null}
          <div className="ms-auto flex items-center gap-3">
            <Button size="sm" variant="ghost" onClick={() => void actions().stop()}>
              <X aria-hidden className="size-4" />
              {t("WebClose")}
            </Button>
          </div>
        </div>
      </div>
    </section>
  );
}
