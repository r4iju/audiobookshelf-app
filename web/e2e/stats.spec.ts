import { expect, type Locator, type Page, test } from "@playwright/test";
import { accounts, serverApi, signIn } from "./qa";

const localDate = (date: Date) =>
  `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, "0")}-${String(date.getDate()).padStart(2, "0")}`;

const figure = (page: Page, label: string) =>
  page
    .getByRole("term")
    .filter({ hasText: new RegExp(`^${label}$`) })
    .locator("xpath=following-sibling::dd[1]");

test("statistics show the account's listening as the server records it", async ({ page }) => {
  const api = await serverApi(accounts.other);
  const stats = (await api.call("/api/me/listening-stats")).body;
  const me = (await api.call("/api/me")).body;
  expect(stats.recentSessions.length).toBeGreaterThan(0);

  await signIn(page, accounts.other);
  await page.getByRole("link", { name: "Statistics" }).click();
  await expect(page.getByRole("heading", { level: 1, name: "Your Stats" })).toBeVisible();
  await expect(figure(page, "Items Finished")).toHaveText(
    String(me.mediaProgress.filter((progress: { isFinished: boolean }) => progress.isFinished).length),
  );
  await expect(figure(page, "Days Listened")).toHaveText(String(Object.keys(stats.days).length));
  await expect(figure(page, "Minutes Listening")).toHaveText(String(Math.round(stats.totalTime / 60)));

  const week = page.getByRole("list", { name: "Minutes Listening (last 7 days)" });
  await expect(week.getByRole("listitem")).toHaveCount(7);
  const todayMinutes = Math.round((stats.days[localDate(new Date())] ?? 0) / 60);
  await expect(week.getByRole("listitem").last()).toContainText(`${todayMinutes} minutes`);

  const recent = page.getByRole("list", { name: "Recent Sessions" });
  await expect(recent.getByRole("listitem")).toHaveCount(Math.min(10, stats.recentSessions.length));
  await expect(recent.getByRole("listitem").first()).toContainText(stats.recentSessions[0].displayTitle);
});

test("on a phone, statistics are reachable from the header", async ({ page }) => {
  await page.setViewportSize({ width: 390, height: 844 });
  await signIn(page, accounts.other);
  await page.getByRole("link", { name: "Statistics" }).click();
  await expect(page.getByRole("heading", { level: 1, name: "Your Stats" })).toBeVisible();
});

const top = async (locator: Locator) => (await locator.boundingBox())?.y ?? Number.NaN;

test("in December the year in review leads, with the account's and, for administrators, the server's year", async ({
  page,
}) => {
  const admin = await serverApi(accounts.admin);
  const mine = (await admin.call("/api/me/stats/year/2026")).body;
  const server = (await admin.call("/api/stats/year/2026")).body;
  await page.clock.setFixedTime(new Date(2026, 11, 15, 12));
  await signIn(page, accounts.admin);
  await page.goto("/stats");
  const show = page.getByRole("button", { name: "See Year in Review" });
  await expect(figure(page, "Items Finished")).toBeVisible();
  expect(await top(show)).toBeLessThan(await top(figure(page, "Items Finished")));
  await show.click();

  const review = page.getByRole("region", { name: "2026 in review" });
  await expect(figure(page, "Listening sessions").first()).toHaveText(String(mine.totalListeningSessions));
  await expect(review).toContainText(`${mine.numBooksListened}`);

  const onServer = page.getByRole("region", { name: "2026 on this server" });
  await expect(onServer).toContainText(String(server.numBooksAdded));
  await expect(onServer).toContainText(server.topGenres[0].genre);
  await expect(onServer).toContainText(server.topNarrators[0].name);
  await expect(onServer).toContainText("2.6 MB");
  await expect(
    onServer.locator(`img[src*="/api/items/${server.booksAddedWithCovers[0]}/cover"]`),
  ).toHaveCount(1);

  const refreshed = page.waitForRequest((request) => request.url().includes("/api/stats/year/2026"));
  await onServer.getByRole("button", { name: "Refresh" }).click();
  await refreshed;

  await page.getByRole("button", { name: "Hide Year in Review" }).click();
  await expect(review).toHaveCount(0);
});

test("the rest of the year last year's review follows the sessions, and others do not see the server's year", async ({
  page,
}) => {
  const api = await serverApi(accounts.other);
  const year = (await api.call("/api/me/stats/year/2026")).body;
  await page.clock.setFixedTime(new Date(2026, 9, 2, 12));
  await signIn(page, accounts.other);
  await page.goto("/stats");
  const show = page.getByRole("button", { name: "See Year in Review" });
  await expect(page.getByRole("list", { name: "Recent Sessions" })).toBeVisible();
  expect(await top(show)).toBeGreaterThan(await top(page.getByRole("list", { name: "Recent Sessions" })));
  await show.click();
  await expect(page.getByRole("region", { name: "2025 in review" })).toBeVisible();

  await page.clock.setFixedTime(new Date(2027, 0, 10, 12));
  await page.reload();
  await page.getByRole("button", { name: "See Year in Review" }).click();
  const review = page.getByRole("region", { name: "2026 in review" });
  await expect(review).toContainText(year.topAuthors[0].name);
  await expect(review.locator(`img[src*="/api/items/${year.booksWithCovers[0]}/cover"]`)).toHaveCount(1);
  await expect(page.getByRole("region", { name: "2026 on this server" })).toHaveCount(0);
});
