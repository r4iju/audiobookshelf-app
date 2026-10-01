import { expect, test } from "@playwright/test";
import { accounts, qa, signIn } from "./qa";

test("password sign-in reaches the library and survives a reload", async ({ page }) => {
  await signIn(page);
  const nav = page.getByRole("navigation", { name: "Library" });
  await expect(nav.getByRole("link", { name: "Audiobooks" })).toBeVisible();
  await expect(nav.getByRole("link", { name: "Podcasts" })).toBeVisible();
  await expect(
    page
      .getByRole("heading", { name: "Continue Listening" })
      .or(page.getByRole("heading", { name: "Recently Added" }))
      .first(),
  ).toBeVisible();

  await page.reload();
  await expect(page.getByRole("navigation", { name: "Library" })).toBeVisible();
  const stored = await page.evaluate(() => JSON.stringify(localStorage));
  expect(stored).not.toContain(accounts.user.password);
});

test("a wrong password explains the failure and keeps the server", async ({ page }) => {
  await page.goto("/connect");
  await page.getByLabel("Server address").fill(qa.origin);
  await page.getByRole("button", { name: "Continue" }).click();
  await page.getByLabel("Username").fill(accounts.user.username);
  await page.getByLabel("Password").fill("not-the-password");
  await page.getByRole("button", { name: "Sign in" }).click();
  await expect(page.getByRole("main").getByRole("alert")).toContainText(/username or password/i);
  await expect(page.getByLabel("Username")).toHaveValue(accounts.user.username);
});

test("an unreachable server address is reported without signing in", async ({ page }) => {
  await page.goto("/connect");
  await page.getByLabel("Server address").fill("http://127.0.0.1:19899");
  await page.getByRole("button", { name: "Continue" }).click();
  await expect(page.getByRole("main").getByRole("alert")).toContainText(/could not reach/i);
});
