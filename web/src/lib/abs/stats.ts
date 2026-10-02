/** Seconds listened per local date (`yyyy-MM-dd`), as `/api/me/listening-stats` reports `days`. */
export type ListeningDays = Record<string, number>;

export interface ListeningDay {
  date: string;
  day: Date;
  minutes: number;
}

export const localDate = (date: Date) =>
  `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, "0")}-${String(date.getDate()).padStart(2, "0")}`;

const daysBefore = (today: Date, count: number) =>
  new Date(today.getFullYear(), today.getMonth(), today.getDate() - count);

/** The last seven days ending today, each in whole minutes as the legacy chart rounds them. */
export function lastSevenDays(days: ListeningDays, today: Date): ListeningDay[] {
  return Array.from({ length: 7 }, (_, index) => {
    const day = daysBefore(today, 6 - index);
    const date = localDate(day);
    return { date, day, minutes: Math.round((days[date] ?? 0) / 60) };
  });
}

export function weekSummary(week: readonly ListeningDay[]) {
  const total = week.reduce((sum, day) => sum + day.minutes, 0);
  return { total, average: Math.round(total / 7), best: Math.max(0, ...week.map((day) => day.minutes)) };
}

/** Consecutive days listened up to yesterday, plus today once something was heard today. */
export function daysInARow(days: ListeningDays, today: Date) {
  let count = 0;
  while (days[localDate(daysBefore(today, count + 1))]) count++;
  return days[localDate(today)] ? count + 1 : count;
}

/** Like the legacy app, December reviews the year so far and every other month the year before; December and January lead with it. */
export function reviewYear(now: Date) {
  const month = now.getMonth();
  return {
    year: month === 11 ? now.getFullYear() : now.getFullYear() - 1,
    featured: month === 11 || month === 0,
  };
}

const byteUnits = ["byte", "kilobyte", "megabyte", "gigabyte", "terabyte", "petabyte"] as const;

/** Binary multiples, as the legacy app sizes libraries, ready for a unit-style `Intl.NumberFormat`. */
export function byteSize(bytes: number): { value: number; unit: (typeof byteUnits)[number] } {
  const power = bytes > 0 ? Math.min(Math.floor(Math.log(bytes) / Math.log(1024)), byteUnits.length - 1) : 0;
  return { value: Math.round((bytes / 1024 ** power) * 10) / 10, unit: byteUnits[power] ?? "byte" };
}

const minute = ["minute", 60_000] as const;
const units = [
  ["year", 365 * 86_400_000],
  ["month", 30 * 86_400_000],
  ["day", 86_400_000],
  ["hour", 3_600_000],
  minute,
] as const;

/** How long ago a moment was, in the largest whole unit, ready for `Intl.RelativeTimeFormat`. */
export function timeAgo(then: number, now: number): { value: number; unit: (typeof units)[number][0] } {
  const elapsed = Math.max(0, now - then);
  const [unit, size] = units.find(([, size]) => elapsed >= size) ?? minute;
  // `|| 0` turns -0 into 0 so a moment ago reads the same in every locale.
  return { value: -Math.floor(elapsed / size) || 0, unit };
}
