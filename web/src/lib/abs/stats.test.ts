import { describe, expect, it } from "vitest";
import { byteSize, daysInARow, lastSevenDays, reviewYear, timeAgo, weekSummary } from "./stats";

const today = new Date(2026, 9, 2, 15, 0);

describe("lastSevenDays", () => {
  it("lists the six days before today and today, in whole minutes by local date", () => {
    const week = lastSevenDays(
      { "2026-10-02": 3_000, "2026-09-30": 89, "2026-09-25": 600, "2026-09-26": 29 },
      today,
    );
    expect(week.map((day) => day.date)).toEqual([
      "2026-09-26",
      "2026-09-27",
      "2026-09-28",
      "2026-09-29",
      "2026-09-30",
      "2026-10-01",
      "2026-10-02",
    ]);
    expect(week.map((day) => day.minutes)).toEqual([0, 0, 0, 0, 1, 0, 50]);
  });
});

describe("weekSummary", () => {
  it("totals the week's minutes with the average per day and the best day", () => {
    const week = lastSevenDays({ "2026-10-02": 3_000, "2026-10-01": 1_200, "2026-09-30": 60 }, today);
    expect(weekSummary(week)).toEqual({ total: 71, average: 10, best: 50 });
  });
});

describe("daysInARow", () => {
  it("counts the days up to yesterday, and today once something was heard today", () => {
    const days = { "2026-09-29": 10, "2026-09-30": 10, "2026-10-01": 10 };
    expect(daysInARow(days, today)).toBe(3);
    expect(daysInARow({ ...days, "2026-10-02": 5 }, today)).toBe(4);
    expect(daysInARow({ "2026-10-02": 5, "2026-09-30": 10 }, today)).toBe(1);
    expect(daysInARow({ ...days, "2026-09-30": 0 }, today)).toBe(1);
    expect(daysInARow({}, today)).toBe(0);
  });
});

describe("reviewYear", () => {
  it("reviews this year in December and last year otherwise, featured in December and January", () => {
    expect(reviewYear(new Date(2026, 11, 1))).toEqual({ year: 2026, featured: true });
    expect(reviewYear(new Date(2027, 0, 31))).toEqual({ year: 2026, featured: true });
    expect(reviewYear(today)).toEqual({ year: 2025, featured: false });
  });
});

describe("byteSize", () => {
  it("uses the largest binary unit that keeps the number at one or more, with one decimal", () => {
    expect(byteSize(512)).toEqual({ value: 512, unit: "byte" });
    expect(byteSize(2_702_731)).toEqual({ value: 2.6, unit: "megabyte" });
    expect(byteSize(5 * 1024 ** 4)).toEqual({ value: 5, unit: "terabyte" });
    expect(byteSize(0)).toEqual({ value: 0, unit: "byte" });
  });
});

describe("timeAgo", () => {
  const now = today.getTime();
  it("names the largest whole unit that has passed", () => {
    expect(timeAgo(now - 20_000, now)).toEqual({ value: 0, unit: "minute" });
    expect(timeAgo(now - 5 * 60_000, now)).toEqual({ value: -5, unit: "minute" });
    expect(timeAgo(now - 3 * 3_600_000, now)).toEqual({ value: -3, unit: "hour" });
    expect(timeAgo(now - 2 * 86_400_000, now)).toEqual({ value: -2, unit: "day" });
    expect(timeAgo(now - 45 * 86_400_000, now)).toEqual({ value: -1, unit: "month" });
    expect(timeAgo(now - 800 * 86_400_000, now)).toEqual({ value: -2, unit: "year" });
  });
});
