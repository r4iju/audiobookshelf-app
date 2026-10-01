import { execFileSync } from "node:child_process";
import { expect, type Page, test } from "@playwright/test";
import { clearProgress, itemIdByTitle, qa, serverApi, signIn } from "./qa";

// "The Long Tide": three 30 s MP3 files, one chapter per file. Chromium plays MP3 natively.

const player = (page: Page) => page.getByRole("region", { name: "Player" });
const position = (page: Page) => player(page).getByRole("slider", { name: "Seek" }).inputValue().then(Number);

async function fresh(account = { username: "qa-other", password: "qa-other-pass" } as const) {
  const api = await serverApi(account);
  const id = await itemIdByTitle("The Long Tide");
  await clearProgress(api, id);
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

test("listening held by a delete that may still be running is sent once a restart the user was asked for is confirmed", async ({
  page,
}) => {
  test.setTimeout(120_000);
  const { api, id, account } = await fresh();
  await signIn(page, account);
  // A record left by a discard whose delete may still be running, which no discard of this browser is finishing.
  await page.evaluate(async () => {
    const { activeId } = JSON.parse(localStorage.getItem("abs-web:v1:connections") ?? "{}");
    const db = await new Promise<IDBDatabase>((resolve, reject) => {
      const request = indexedDB.open("abs-web-coordination", 1);
      request.onupgradeneeded = () => request.result.createObjectStore("entries", { keyPath: "key" });
      request.onsuccess = () => resolve(request.result);
      request.onerror = () => reject(request.error);
    });
    await new Promise<void>((resolve, reject) => {
      const transaction = db.transaction("entries", "readwrite");
      transaction.objectStore("entries").put({ key: `block:${activeId}:gone`, phase: "deleting" });
      transaction.oncomplete = () => resolve();
      transaction.onabort = () => reject(transaction.error);
    });
    db.close();
  });
  await page.goto(`/item/${id}`);
  await page.getByRole("button", { name: /^Play/ }).click();
  await expect.poll(() => position(page), { timeout: 15_000 }).toBeGreaterThan(4);
  await player(page).getByRole("button", { name: "Pause", exact: true }).click();
  await expect(page.getByText(/waiting to sync/)).toBeVisible({ timeout: 20_000 });

  const notice = page.getByRole("alert").filter({ hasText: "held back" });
  await expect(notice).toContainText(qa.origin);
  expect((await api.call(`/api/me/progress/${id}`)).status).toBe(404);
  await notice.getByRole("button", { name: "Restart the server" }).click();
  await expect(notice).toContainText(`Restart the Audiobookshelf server at ${qa.origin} now`);
  await expect(notice).toContainText(
    "if it did not, a delete still running there can remove progress sent after",
  );

  execFileSync("docker", ["restart", "abs-web-qa"]);
  execFileSync("node", ["qa/server.mjs", "up"], { stdio: "ignore" });
  await notice.getByRole("button", { name: "I restarted the server" }).click();

  await expect(notice).toHaveCount(0);
  await expect
    .poll(async () => (await api.call(`/api/me/progress/${id}`)).body?.currentTime ?? 0, { timeout: 30_000 })
    .toBeGreaterThan(4);
});
