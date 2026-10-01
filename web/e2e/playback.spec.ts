import { expect, type Page, test } from "@playwright/test";
import { qa, serverApi, signIn } from "./qa";

// "The Long Tide": three 30 s MP3 files, one chapter per file. Chromium plays MP3 natively.

async function itemIdByTitle(title: string) {
  const api = await serverApi({ username: "qa-admin", password: "qa-admin-pass" });
  const { body } = await api.call(
    `/api/libraries/${qa.libraries.books}/search?q=${encodeURIComponent(title)}`,
  );
  return body.book[0].libraryItem.id as string;
}

const player = (page: Page) => page.getByRole("region", { name: "Player" });
const position = (page: Page) => player(page).getByRole("slider", { name: "Seek" }).inputValue().then(Number);

async function fresh(account = { username: "qa-other", password: "qa-other-pass" } as const) {
  const api = await serverApi(account);
  const id = await itemIdByTitle("The Long Tide");
  const progress = await api.call(`/api/me/progress/${id}`);
  if (progress.body?.id) await api.call(`/api/me/progress/${progress.body.id}`, { method: "DELETE" });
  const me = await api.call("/api/me");
  for (const bookmark of me.body.bookmarks ?? []) {
    await api.call(`/api/me/item/${bookmark.libraryItemId}/bookmark/${bookmark.time}`, { method: "DELETE" });
  }
  return { api, id, account };
}

test("a multi-file book plays across files and its progress reaches the server", async ({ page }) => {
  const { api, id, account } = await fresh();
  await signIn(page, account);
  await page.goto(`/item/${id}`);
  await page.getByRole("button", { name: /^Play/ }).click();
  await expect(player(page)).toContainText("The Long Tide");
  await expect.poll(() => position(page), { timeout: 15_000 }).toBeGreaterThan(1);

  await player(page).getByRole("button", { name: "Next chapter" }).click();
  await expect.poll(() => position(page), { timeout: 15_000 }).toBeGreaterThan(31);
  await player(page).getByRole("button", { name: "Pause", exact: true }).click();

  await expect
    .poll(async () => (await api.call(`/api/me/progress/${id}`)).body?.currentTime ?? 0, { timeout: 20_000 })
    .toBeGreaterThan(30);
  const sessions = await api.call(`/api/me/listening-sessions?itemsPerPage=5`);
  expect(sessions.body.sessions[0].libraryItemId).toBe(id);
  expect(sessions.body.sessions[0].timeListening).toBeGreaterThan(0);
});

test("a reload brings the player back at the same position", async ({ page }) => {
  const { id, account } = await fresh();
  await signIn(page, account);
  await page.goto(`/item/${id}`);
  await page.getByRole("button", { name: /^Play/ }).click();
  await expect.poll(() => position(page), { timeout: 15_000 }).toBeGreaterThan(3);
  await player(page).getByRole("button", { name: "Pause", exact: true }).click();
  const before = await position(page);

  await page.reload();
  await expect(player(page)).toContainText("The Long Tide");
  expect(Math.abs((await position(page)) - before)).toBeLessThan(2);
  await player(page).getByRole("button", { name: "Play", exact: true }).click();
  await expect.poll(() => position(page), { timeout: 15_000 }).toBeGreaterThan(before + 1);
});

test("listening while the server is unreachable is kept and delivered later", async ({ page }) => {
  const { api, id, account } = await fresh();
  await signIn(page, account);
  await page.goto(`/item/${id}`);
  await page.route(`${qa.origin}/api/session/local-all`, (route) => route.abort("internetdisconnected"));
  await page.getByRole("button", { name: /^Play/ }).click();
  await expect.poll(() => position(page), { timeout: 15_000 }).toBeGreaterThan(4);
  await player(page).getByRole("button", { name: "Pause", exact: true }).click();
  await expect(page.getByText(/waiting to sync/)).toBeVisible({ timeout: 20_000 });
  expect((await api.call(`/api/me/progress/${id}`)).status).toBe(404);

  await page.unroute(`${qa.origin}/api/session/local-all`);
  await page.reload();
  await expect
    .poll(async () => (await api.call(`/api/me/progress/${id}`)).body?.currentTime ?? 0, { timeout: 30_000 })
    .toBeGreaterThan(4);
});

test("the sleep timer can stop at the end of the chapter", async ({ page }) => {
  const { id, account } = await fresh();
  await signIn(page, account);
  await page.goto(`/item/${id}`);
  await page.getByRole("button", { name: /^Play/ }).click();
  await expect.poll(() => position(page), { timeout: 15_000 }).toBeGreaterThan(0.5);
  await player(page).getByRole("slider", { name: "Seek" }).fill("26");
  await player(page).getByLabel("Sleep timer").selectOption({ label: "End of Chapter" });
  await expect(player(page).getByRole("button", { name: "Play", exact: true })).toBeVisible({
    timeout: 15_000,
  });
  const stoppedAt = await position(page);
  expect(stoppedAt).toBeGreaterThan(28);
  expect(stoppedAt).toBeLessThan(31);
});

test("speed and bookmarks are kept", async ({ page }) => {
  const { api, id, account } = await fresh();
  await signIn(page, account);
  await page.goto(`/item/${id}`);
  await page.getByRole("button", { name: /^Play/ }).click();
  await expect.poll(() => position(page), { timeout: 15_000 }).toBeGreaterThan(1);
  await player(page).getByLabel("Playback Speed", { exact: true }).selectOption("1.5");
  await player(page).getByRole("button", { name: "Create Bookmark" }).click();
  await expect.poll(async () => (await api.call("/api/me")).body.bookmarks.length).toBe(1);

  await page.reload();
  await expect(player(page).getByLabel("Playback Speed", { exact: true })).toHaveValue("1.5");
});
