"use client";

import type { UseQueryResult } from "@tanstack/react-query";
import { RefreshCw } from "lucide-react";
import { type ReactNode, useState } from "react";
import { Button } from "@/components/ui/button";
import { QueryState } from "@/components/ui/query-state";
import { Section } from "@/components/ui/section";
import { EmptyState } from "@/components/ui/status";
import { formatUnit, useI18n } from "@/i18n/i18n";
import { formatDuration } from "@/lib/abs/media";
import { isAdmin } from "@/lib/abs/permissions";
import { useListeningStats, useMe, useServerYearStats, useYearStats } from "@/lib/abs/queries";
import type { ListeningStats, ServerYearStats, User, YearStats } from "@/lib/abs/schemas";
import { byteSize, daysInARow, lastSevenDays, reviewYear, timeAgo, weekSummary } from "@/lib/abs/stats";
import { useAbs } from "@/lib/session/store";

type Figure = readonly [label: string, value: string];

/** Each label comes before its value for assistive technology; the value shows above it. */
function Figures({ figures, columns }: { figures: readonly Figure[]; columns: 3 | 4 }) {
  return (
    <dl className={`grid gap-3 ${columns === 3 ? "grid-cols-3" : "grid-cols-2 sm:grid-cols-4"}`}>
      {figures.map(([label, value]) => (
        <div key={label} className="flex flex-col-reverse gap-1 rounded-xl bg-surface-2 p-3 sm:p-4">
          <dt className="text-sm text-muted">{label}</dt>
          <dd className="text-xl font-bold tabular-nums sm:text-2xl">{value}</dd>
        </div>
      ))}
    </dl>
  );
}

function useFormats() {
  const { t, locale } = useI18n();
  const number = new Intl.NumberFormat(locale).format;
  return {
    number,
    minutes: (count: number) => `${number(count)} ${t("LabelStatsMinutes")}`,
    duration: (seconds: number) => formatDuration(seconds) || number(0),
    bytes: (bytes: number) => {
      const { value, unit } = byteSize(bytes);
      return formatUnit(locale, value, unit);
    },
  };
}

export function StatsScreen() {
  const { t } = useI18n();
  const stats = useListeningStats();
  const me = useMe();
  const review = reviewYear(new Date());
  const yearReview = <YearReview year={review.year} admin={isAdmin(me.data)} />;

  return (
    <div className="mx-auto flex w-full max-w-3xl flex-col gap-6">
      <h1 className="text-2xl font-bold">{t("HeaderYourStats")}</h1>
      {review.featured ? yearReview : null}
      <QueryState query={stats}>
        {(listening) => (
          <QueryState query={me}>{(user) => <Listening stats={listening} me={user} />}</QueryState>
        )}
      </QueryState>
      {review.featured ? null : yearReview}
    </div>
  );
}

const finishedCount = (me: User) => me.mediaProgress.filter((progress) => progress.isFinished).length;

function Listening({ stats, me }: { stats: ListeningStats; me: User }) {
  const { t, locale } = useI18n();
  const { number, minutes, duration } = useFormats();
  const today = new Date();
  const week = lastSevenDays(stats.days, today);
  const summary = weekSummary(week);
  const best = Math.max(summary.best, 1);
  const weekday = (format: "short" | "long") => new Intl.DateTimeFormat(locale, { weekday: format }).format;
  const relative = new Intl.RelativeTimeFormat(locale, { numeric: "auto" });

  return (
    <>
      <Figures
        columns={3}
        figures={[
          [t("LabelStatsItemsFinished"), number(finishedCount(me))],
          [t("LabelStatsDaysListened"), number(Object.keys(stats.days).length)],
          [t("LabelStatsMinutesListening"), number(Math.round(stats.totalTime / 60))],
        ]}
      />

      <Section title={t("HeaderStatsMinutesListeningChart")}>
        <ol aria-label={t("HeaderStatsMinutesListeningChart")} className="grid grid-cols-7 gap-2">
          {week.map((day) => (
            <li key={day.date} className="flex flex-col items-center gap-1.5">
              <span className="sr-only">{weekday("long")(day.day)} </span>
              <span className="text-xs font-semibold tabular-nums">
                {number(day.minutes)}
                <span className="sr-only"> {t("LabelStatsMinutes")}</span>
              </span>
              <span aria-hidden className="flex h-32 w-full items-end rounded-lg bg-surface-2">
                <span
                  className="w-full rounded-lg bg-accent"
                  style={{ height: `${Math.max(day.minutes ? 4 : 0, (day.minutes / best) * 100)}%` }}
                />
              </span>
              <span aria-hidden className="text-xs text-muted">
                {weekday("short")(day.day)}
              </span>
            </li>
          ))}
        </ol>
        <Figures
          columns={4}
          figures={[
            [t("LabelStatsWeekListening"), minutes(summary.total)],
            [t("LabelStatsDailyAverage"), minutes(summary.average)],
            [t("LabelStatsBestDay"), minutes(summary.best)],
            [`${t("LabelStatsDays")} ${t("LabelStatsInARow")}`, number(daysInARow(stats.days, today))],
          ]}
        />
      </Section>

      <Section title={t("HeaderStatsRecentSessions")}>
        {stats.recentSessions.length ? (
          <ol aria-label={t("HeaderStatsRecentSessions")} className="flex flex-col divide-y divide-line">
            {stats.recentSessions.slice(0, 10).map((session) => {
              const ago = timeAgo(session.updatedAt, today.getTime());
              return (
                <li key={session.id} className="flex items-baseline justify-between gap-4 py-3">
                  <span className="min-w-0">
                    <span className="block truncate font-medium">{session.displayTitle}</span>
                    <span className="text-sm text-muted">{relative.format(ago.value, ago.unit)}</span>
                  </span>
                  <span className="shrink-0 text-sm tabular-nums">{duration(session.timeListening)}</span>
                </li>
              );
            })}
          </ol>
        ) : (
          <EmptyState title={t("MessageNoListeningSessions")} />
        )}
      </Section>
    </>
  );
}

function YearReview({ year, admin }: { year: number; admin: boolean }) {
  const { t } = useI18n();
  const [shown, setShown] = useState(false);
  return (
    <>
      <div>
        <Button variant={shown ? "secondary" : "primary"} onClick={() => setShown(!shown)}>
          {t(shown ? "LabelYearReviewHide" : "LabelYearReviewShow")}
        </Button>
      </div>
      {shown ? (
        <>
          <YourYear year={year} />
          {admin ? <ServerYear year={year} /> : null}
        </>
      ) : null}
    </>
  );
}

/** A year's section, refreshable because the year in progress keeps changing. */
function YearSection<T>({
  title,
  query,
  children,
}: {
  title: string;
  query: UseQueryResult<T>;
  children: (data: T) => ReactNode;
}) {
  const { t } = useI18n();
  return (
    <Section title={title}>
      <QueryState query={query}>{children}</QueryState>
      <div className="flex justify-end">
        <Button size="sm" variant="ghost" disabled={query.isFetching} onClick={() => void query.refetch()}>
          <RefreshCw aria-hidden className="size-4" />
          {t("WebRefresh")}
        </Button>
      </div>
    </Section>
  );
}

type Ranked = YearStats["topAuthors"][number];

function TopList({ title, entries }: { title: string; entries: readonly Ranked[] }) {
  const { duration } = useFormats();
  if (!entries.length) return null;
  return (
    <div className="flex flex-col gap-2">
      <h3 className="text-sm font-semibold">{title}</h3>
      <ol className="flex flex-col gap-1 text-sm">
        {entries.map((entry) => (
          <li key={entry.name} className="flex justify-between gap-3">
            <span className="truncate">{entry.name}</span>
            <span className="shrink-0 text-muted tabular-nums">{duration(entry.time)}</span>
          </li>
        ))}
      </ol>
    </div>
  );
}

/** The legacy share images showed these covers without titles, so they stay decorative here. */
function CoverStrip({ itemIds }: { itemIds: readonly string[] }) {
  const { client } = useAbs();
  if (!itemIds.length) return null;
  return (
    <ul aria-hidden className="flex gap-2 overflow-x-auto pb-1">
      {itemIds.slice(0, 12).map((id) => (
        <li key={id} className="w-16 shrink-0">
          <img
            src={client.url(`/api/items/${id}/cover`)}
            alt=""
            loading="lazy"
            className="aspect-square w-full rounded-lg bg-surface-2 object-cover"
          />
        </li>
      ))}
    </ul>
  );
}

function YourYear({ year }: { year: number }) {
  const { t } = useI18n();
  return (
    <YearSection title={t("WebYearInReview", String(year))} query={useYearStats(year)}>
      {(stats) => <YourYearBody year={year} stats={stats} />}
    </YearSection>
  );
}

function YourYearBody({ year, stats }: { year: number; stats: YearStats }) {
  const { t, locale } = useI18n();
  const { number, duration } = useFormats();
  const month = stats.mostListenedMonth;
  return (
    <>
      <CoverStrip itemIds={[...new Set([...stats.finishedBooksWithCovers, ...stats.booksWithCovers])]} />
      <Figures
        columns={4}
        figures={[
          [t("WebListeningSessions"), number(stats.totalListeningSessions)],
          [t("WebTotalListening"), duration(stats.totalListeningTime)],
          [t("WebBooksListened"), number(stats.numBooksListened)],
          [t("WebBooksFinished"), number(stats.numBooksFinished)],
        ]}
      />
      {stats.totalListeningSessions ? (
        <div className="grid gap-4 sm:grid-cols-2">
          <TopList title={t("WebTopAuthors")} entries={stats.topAuthors} />
          <TopList title={t("WebTopGenres")} entries={stats.topGenres} />
          {stats.mostListenedNarrator ? (
            <TopList title={t("WebMostListenedNarrator")} entries={[stats.mostListenedNarrator]} />
          ) : null}
          {month ? (
            <TopList
              title={t("WebMostListenedMonth")}
              entries={[
                {
                  name: new Intl.DateTimeFormat(locale, { month: "long" }).format(
                    new Date(year, month.month),
                  ),
                  time: month.time,
                },
              ]}
            />
          ) : null}
        </div>
      ) : (
        <p className="text-sm text-muted">{t("WebNoYearListening")}</p>
      )}
    </>
  );
}

function ServerYear({ year }: { year: number }) {
  const { t } = useI18n();
  return (
    <YearSection title={t("WebYearOnServer", String(year))} query={useServerYearStats(year)}>
      {(stats) => <ServerYearBody stats={stats} />}
    </YearSection>
  );
}

function Growth({ label, total, added }: { label: string; total: string; added: string }) {
  const { t } = useI18n();
  return (
    <div className="flex flex-col-reverse gap-0.5 rounded-xl bg-surface-2 p-3 sm:p-4">
      <dt className="text-muted">{label}</dt>
      <dd>
        <span className="text-lg font-bold tabular-nums">{total}</span>{" "}
        <span className="text-muted">{t("WebAddedAmount", added)}</span>
      </dd>
    </div>
  );
}

function ServerYearBody({ stats }: { stats: ServerYearStats }) {
  const { t } = useI18n();
  const { number, duration, bytes } = useFormats();
  return (
    <>
      <CoverStrip itemIds={stats.booksAddedWithCovers} />
      <Figures
        columns={4}
        figures={[
          [t("WebListeningSessions"), number(stats.numListeningSessions)],
          [t("WebTotalListening"), duration(stats.totalListeningTime)],
          [t("WebBooksAdded"), number(stats.numBooksAdded)],
          [t("WebAuthorsAdded"), number(stats.numAuthorsAdded)],
        ]}
      />
      <dl className="grid grid-cols-2 gap-3 text-sm">
        <Growth
          label={t("WebLibrarySize")}
          total={bytes(stats.totalBooksSize)}
          added={bytes(stats.totalBooksAddedSize)}
        />
        <Growth
          label={t("WebLibraryDuration")}
          total={duration(stats.totalBooksDuration)}
          added={duration(stats.totalBooksAddedDuration)}
        />
      </dl>
      <div className="grid gap-4 sm:grid-cols-3">
        <TopList title={t("WebTopAuthors")} entries={stats.topAuthors} />
        <TopList title={t("WebTopNarrators")} entries={stats.topNarrators} />
        <TopList title={t("WebTopGenres")} entries={stats.topGenres} />
      </div>
    </>
  );
}
