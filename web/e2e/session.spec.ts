import { expect, test } from "@playwright/test";
import { accounts, clearProgress, itemIdByTitle, serverApi, signIn } from "./qa";

test("an ended session asks to sign in again and returns to the same page", async ({ page }) => {
  await signIn(page);
  const id = await itemIdByTitle("Salt and Signal");
  await page.goto(`/item/${id}`);
  await expect(page.getByRole("heading", { level: 1, name: "Salt and Signal" })).toBeVisible();

  await page.evaluate(() => {
    const key = "abs-web:v1:connections";
    const registry = JSON.parse(localStorage.getItem(key) ?? "{}");
    for (const entry of registry.connections) {
      if (entry.auth) entry.auth = { kind: "token", accessToken: "expired", refreshToken: "revoked" };
    }
    localStorage.setItem(key, JSON.stringify(registry));
  });
  await page.reload();

  const banner = page.getByRole("alert").filter({ hasText: /session on this server has ended/i });
  await expect(banner).toBeVisible();
  await banner.getByRole("link", { name: "Sign in" }).click();
  await expect(page.getByLabel("Username")).toHaveValue(accounts.user.username);
  await page.getByLabel("Password").fill(accounts.user.password);
  await page.getByRole("button", { name: "Sign in" }).click();

  await expect(page.getByRole("heading", { level: 1, name: "Salt and Signal" })).toBeVisible();
  await expect(banner).toHaveCount(0);
});

test("progress from another device appears without reloading", async ({ page }) => {
  const api = await serverApi(accounts.user);
  const id = await itemIdByTitle("Salt and Signal");
  await clearProgress(api, id);
  await signIn(page);
  await page.goto(`/item/${id}`);
  await expect(page.getByRole("heading", { level: 1, name: "Salt and Signal" })).toBeVisible();
  const progress = page.getByRole("progressbar", { name: "Your Progress" });
  await expect(progress).toHaveCount(0);

  await api.call(`/api/me/progress/${id}`, {
    method: "PATCH",
    body: { currentTime: 30, duration: 60, progress: 0.5 },
  });
  await expect(progress).toHaveAttribute("aria-valuenow", "50");
});

test("finishing and discarding progress reach the server", async ({ page }) => {
  const api = await serverApi(accounts.user);
  const id = await itemIdByTitle("Salt and Signal");
  await clearProgress(api, id);
  await api.call(`/api/me/progress/${id}`, {
    method: "PATCH",
    body: { currentTime: 20, duration: 60, progress: 0.33 },
  });
  const server = async () => (await api.call(`/api/me/progress/${id}`)).body;

  await signIn(page);
  await page.goto(`/item/${id}`);
  await page.getByRole("button", { name: "Mark as finished" }).click();
  await expect.poll(async () => (await server())?.isFinished).toBe(true);

  await page.getByRole("button", { name: "Mark as not finished" }).click();
  await expect.poll(async () => (await server())?.isFinished).toBe(false);

  await page.getByRole("button", { name: "Discard progress" }).click();
  await page.getByRole("dialog").getByRole("button", { name: "Discard progress" }).click();
  await expect.poll(async () => (await api.call(`/api/me/progress/${id}`)).status).toBe(404);
  await expect(page.getByRole("progressbar", { name: "Your Progress" })).toHaveCount(0);
});

test("discarding the progress of the book in the player starts it over on this device too", async ({
  page,
}) => {
  const api = await serverApi(accounts.user);
  const id = await itemIdByTitle("Salt and Signal");
  await clearProgress(api, id);
  await api.call(`/api/me/progress/${id}`, {
    method: "PATCH",
    body: { currentTime: 40, duration: 60, progress: 0.66 },
  });
  const server = async () => (await api.call(`/api/me/progress/${id}`)).body;

  await signIn(page);
  await page.goto(`/item/${id}`);
  await page.getByRole("button", { name: /^Play/ }).click();
  const player = page.getByRole("region", { name: "Player" });
  const position = () => player.getByRole("slider", { name: "Seek" }).inputValue().then(Number);
  await expect.poll(position, { timeout: 15_000 }).toBeGreaterThan(41);
  await player.getByRole("button", { name: "Pause", exact: true }).click();
  await expect.poll(async () => (await server())?.currentTime).toBeGreaterThan(41);

  await page.getByRole("button", { name: "Discard progress" }).click();
  await page.getByRole("dialog").getByRole("button", { name: "Discard progress" }).click();
  await expect.poll(async () => (await api.call(`/api/me/progress/${id}`)).status).toBe(404);
  await expect.poll(position).toBe(0);

  await page.reload();
  await expect.poll(position).toBe(0);
  await player.getByRole("button", { name: "Play", exact: true }).click();
  await expect.poll(position, { timeout: 15_000 }).toBeGreaterThan(1);
  await player.getByRole("button", { name: "Pause", exact: true }).click();
  await expect.poll(async () => (await server())?.currentTime).toBeGreaterThan(1);
  expect((await server()).currentTime).toBeLessThan(20);
});
