"use client";

import {
  Bookmark,
  BookmarkCheck,
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
import { useState } from "react";
import { Cover } from "@/components/media/cover";
import { Button } from "@/components/ui/button";
import { InlineToggle } from "@/components/ui/field";
import { SelectField } from "@/components/ui/select";
import { Alert } from "@/components/ui/status";
import { formatUnit, type Translate, useI18n } from "@/i18n/i18n";
import { formatClock } from "@/lib/abs/media";
import { useCreateBookmark } from "@/lib/abs/mutations";
import { type Player, type Sleep, usePlayer, usePlayerStore } from "@/lib/player/store";
import { chapterIndexAt, nextChapterStart, previousChapterStart } from "@/lib/player/timeline";
import { ratePresets, sleepPresetsMinutes, useSettings, useSettingsStore } from "@/lib/settings/store";
import { BookmarksDialog } from "./bookmarks";
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

/** Sits in the page's flow under its scrolling box; `fullWindow` when nothing follows it, as while reading. */
export function PlayerDock({ fullWindow = false }: { fullWindow?: boolean }) {
  const player = usePlayer();
  const pending = useProgressSync();
  const { t } = useI18n();
  if (player.phase !== "active") {
    // Floats over the end of the page, just above whatever follows the dock's place.
    return pending > 0 ? (
      <div className="relative">
        <p role="status" className="absolute end-4 bottom-3 z-30 rounded-full bg-surface-2 px-3 py-1 text-xs">
          {t("WebPendingProgress", pending)}
        </p>
      </div>
    ) : null;
  }
  return <Dock player={player} pending={pending} fullWindow={fullWindow} />;
}

function Dock({ player, pending, fullWindow }: { player: Active; pending: number; fullWindow: boolean }) {
  const { t, locale } = useI18n();
  const settings = useSettings();
  const updateSettings = useSettingsStore((state) => state.update);
  const sleep = usePlayerStore((state) => state.sleep);
  const actions = usePlayerStore.getState;
  const createBookmark = useCreateBookmark();
  const expanded = settings.playerExpanded;
  const [bookmarksOpen, setBookmarksOpen] = useState(false);
  const { media, currentTime, status } = player;
  const chapters = media.chapters;
  const chapterIndex = chapterIndexAt(chapters, currentTime);
  const chapter = chapters[chapterIndex];
  const range =
    settings.useChapterTrack && chapter
      ? { min: chapter.start, max: chapter.end }
      : { min: 0, max: media.duration };
  const speed = settings.playbackRate;
  // As in the legacy player, remaining time is always at the current speed; the setting changes elapsed time only.
  const elapsed = (currentTime - range.min) / (settings.scaleElapsedTimeBySpeed ? speed : 1);
  const remaining = (range.max - currentTime) / speed;
  const error = errorText(t, player);
  const rateOptions = (ratePresets as readonly number[]).includes(speed)
    ? ratePresets
    : [...ratePresets, speed].sort((a, b) => a - b);
  const phoneSecondary = expanded ? undefined : "max-[30rem]:hidden";
  const sleepRemaining =
    sleep.kind === "until" ? Math.max(0, Math.round((sleep.endsAt - Date.now()) / 1000)) : 0;

  return (
    <section
      aria-label={t("WebPlayer")}
      className={`relative z-10 border-t border-line bg-surface shadow-[0_-8px_24px_rgb(0_0_0/0.25)] ${fullWindow ? "pb-[env(safe-area-inset-bottom)]" : "lg:pb-[env(safe-area-inset-bottom)]"}`}
    >
      <div className="mx-auto flex max-w-6xl flex-col gap-2 px-4 py-3 lg:px-6">
        {error ? <Alert>{error}</Alert> : null}
        <div className="flex flex-wrap items-center gap-x-3 gap-y-2">
          <Link
            href={`/item/${media.itemId}`}
            aria-label={media.title}
            className="w-12 shrink-0 rounded-lg focus-ring"
          >
            <Cover
              src={media.coverUrl}
              title={media.title}
              shape="square"
              missingLabel={t("WebNoCover")}
              compact
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
          {/* On narrow phones the collapsed bar keeps only play and pause beside the title; expanded, all get a row. */}
          <div
            className={`flex items-center gap-1 ${expanded ? "max-[30rem]:order-last max-[30rem]:w-full max-[30rem]:justify-center max-[30rem]:gap-3" : ""}`}
          >
            <Button
              size="icon"
              variant="ghost"
              className={phoneSecondary}
              aria-label={t("WebPreviousChapter")}
              disabled={!chapters.length}
              onClick={() => actions().seek(previousChapterStart(chapters, currentTime))}
            >
              <SkipBack aria-hidden className="size-5 rtl:rotate-180" />
            </Button>
            <Button
              size="icon"
              variant="ghost"
              className={phoneSecondary}
              aria-label={t("WebJumpBack", formatUnit(locale, settings.jumpBackwardsTime, "second"))}
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
              className={phoneSecondary}
              aria-label={t("WebJumpForward", formatUnit(locale, settings.jumpForwardTime, "second"))}
              onClick={() => actions().jump(settings.jumpForwardTime)}
            >
              <RotateCw aria-hidden className="size-5" />
            </Button>
            <Button
              size="icon"
              variant="ghost"
              className={phoneSecondary}
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
          <div className="flex items-center gap-1">
            <Button
              size="icon"
              variant="ghost"
              aria-expanded={expanded}
              aria-label={expanded ? t("WebCollapsePlayer") : t("WebExpandPlayer")}
              onClick={() => updateSettings({ playerExpanded: !expanded })}
            >
              {expanded ? (
                <ChevronDown aria-hidden className="size-5" />
              ) : (
                <ChevronUp aria-hidden className="size-5" />
              )}
            </Button>
            <span aria-hidden className="h-6 w-px bg-line" />
            <Button
              size="icon"
              variant="ghost"
              className="text-muted hover:text-fg"
              aria-label={t("LabelClosePlayer")}
              title={t("LabelClosePlayer")}
              onClick={() => void actions().stop()}
            >
              <X aria-hidden className="size-4" />
            </Button>
          </div>
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

        <div
          className={`${expanded ? "flex" : "hidden"} max-h-[min(24rem,30dvh)] flex-wrap items-end gap-3 overflow-y-auto p-1 -m-1`}
        >
          <SelectField
            size="sm"
            label={t("LabelPlaybackSpeed")}
            value={String(speed)}
            options={rateOptions.map((rate) => ({ value: String(rate), label: `${rate}×` }))}
            onChange={(rate) => updateSettings({ playbackRate: Number(rate) })}
            className="min-w-24"
          />
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
          <SelectField
            size="sm"
            label={t("LabelSleepTimer")}
            value={sleepValue(sleep)}
            options={[
              { value: "off", label: t("LabelOff") },
              ...(sleep.kind === "until"
                ? [{ value: "running", label: t("WebSleepTimerActive", formatClock(sleepRemaining)) }]
                : []),
              ...sleepPresetsMinutes.map((minutes) => ({
                value: String(minutes),
                label: formatUnit(locale, minutes, "minute"),
              })),
              ...(chapters.length ? [{ value: "chapter", label: t("LabelEndOfChapter") }] : []),
            ]}
            onChange={(value) => {
              if (value === "off") actions().setSleep({ kind: "off" });
              else if (value === "chapter" && chapter)
                actions().setSleep({ kind: "chapter-end", at: chapter.end });
              else if (value !== "running")
                actions().setSleep({ kind: "until", endsAt: Date.now() + Number(value) * 60_000 });
            }}
            className="min-w-32"
          />
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
          <div className="flex flex-col gap-1 text-xs font-medium">
            {chapters.length ? (
              <InlineToggle
                label={t("LabelChapterTrack")}
                checked={settings.useChapterTrack}
                onChange={(checked) => updateSettings({ useChapterTrack: checked })}
              />
            ) : null}
            <InlineToggle
              label={t("LabelScaleElapsedTimeBySpeed")}
              checked={settings.scaleElapsedTimeBySpeed}
              onChange={(checked) => updateSettings({ scaleElapsedTimeBySpeed: checked })}
            />
          </div>
          {media.episodeId ? null : (
            <>
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
              <Button size="sm" onClick={() => setBookmarksOpen(true)}>
                <BookmarkCheck aria-hidden className="size-4" />
                {t("LabelYourBookmarks")}
              </Button>
            </>
          )}
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
        </div>
      </div>
      {bookmarksOpen ? (
        <BookmarksDialog
          itemId={media.itemId}
          currentTime={currentTime}
          defaultTitle={
            chapter
              ? `${chapter.title} ${formatClock(currentTime - chapter.start)}`
              : formatClock(currentTime)
          }
          onPick={(time) => {
            setBookmarksOpen(false);
            actions().seek(time);
          }}
          onClose={() => setBookmarksOpen(false)}
        />
      ) : null}
    </section>
  );
}
