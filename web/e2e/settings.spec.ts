import { expect, type Page, test } from "@playwright/test";
import { accounts, choose, clearProgress, itemIdByTitle, qa, serverApi, signIn } from "./qa";

const root = (page: Page) => page.locator("html");
const player = (page: Page) => page.getByRole("region", { name: "Player" });
const position = (page: Page) => player(page).getByRole("slider", { name: "Seek" }).inputValue().then(Number);

async function openSettings(page: Page) {
  await page.getByRole("link", { name: "Settings", exact: true }).click();
  await expect(page.getByRole("heading", { level: 1, name: "Settings" })).toBeVisible();
}

test("display preferences apply at once and are kept after a reload", async ({ page }) => {
  await signIn(page);
  await openSettings(page);

  await choose(page, "Theme", "Light");
  await expect(root(page)).toHaveAttribute("data-theme", "light");
  await page.getByLabel("Reduce motion").check();
  await expect(root(page)).toHaveAttribute("data-reduce-motion", "true");

  await choose(page, "Language", "Deutsch");
  await expect(page.getByRole("heading", { level: 1, name: "Einstellungen" })).toBeVisible();
  await expect(root(page)).toHaveAttribute("lang", "de");

  await page.reload();
  await expect(page.getByRole("heading", { level: 1, name: "Einstellungen" })).toBeVisible();
  await expect(root(page)).toHaveAttribute("data-theme", "light");
  await expect(page.getByRole("combobox", { name: "Farbschema" })).toHaveText("Hell");

  await choose(page, "Sprache", "عربي");
  await expect(root(page)).toHaveAttribute("dir", "rtl");
  await choose(page, "اللغة", "لغة الخادم الافتراضية");
  await expect(page.getByRole("heading", { level: 1, name: "Settings" })).toBeVisible();
  await expect(root(page)).toHaveAttribute("dir", "ltr");
  await choose(page, "Theme", "Dark");
  await page.getByLabel("Reduce motion").uncheck();
});

test("jump times and auto rewind change how the player moves", async ({ page }) => {
  const api = await serverApi(accounts.other);
  const id = await itemIdByTitle("The Long Tide");
  await clearProgress(api, id);
  await page.clock.install();
  await signIn(page, accounts.other);
  await openSettings(page);
  await choose(page, "Jump forwards time", "15 sec");
  await page.getByLabel("Disable auto rewind").uncheck();

  await page.goto(`/item/${id}`);
  await page.getByRole("button", { name: /^Play/ }).click();
  await expect.poll(() => position(page), { timeout: 15_000 }).toBeGreaterThan(1);
  await player(page).getByRole("button", { name: "Jump forward 15 s" }).click();
  await expect.poll(() => position(page)).toBeGreaterThan(16);
  await player(page).getByRole("button", { name: "Pause", exact: true }).click();
  const paused = await position(page);

  // After a two minute pause, playing again starts ten seconds earlier, as the native apps do.
  await page.clock.fastForward("02:00");
  await player(page).getByRole("button", { name: "Play", exact: true }).click();
  await expect.poll(() => position(page)).toBeLessThan(paused - 5);
  expect(await position(page)).toBeGreaterThan(paused - 12);
  await player(page).getByRole("button", { name: "Pause", exact: true }).click();

  // A place chosen while paused is where playback resumes.
  await player(page).getByRole("button", { name: "Jump forward 15 s" }).click();
  await page.clock.fastForward("02:00");
  const chosen = await position(page);
  await player(page).getByRole("button", { name: "Jump back 10 s" }).click();
  await expect.poll(() => position(page)).toBeLessThan(chosen - 9);
  await player(page).getByRole("button", { name: "Play", exact: true }).click();
  await expect(player(page).getByRole("button", { name: "Pause", exact: true })).toBeVisible();
  expect(await position(page)).toBeGreaterThan(chosen - 11.5);
  await player(page).getByRole("button", { name: "Pause", exact: true }).click();
  const again = await position(page);

  await openSettings(page);
  await page.getByLabel("Disable auto rewind").check();
  await page.clock.fastForward("02:00");
  await player(page).getByRole("button", { name: "Play", exact: true }).click();
  await expect.poll(() => position(page), { timeout: 15_000 }).toBeGreaterThan(again + 1);
  await player(page).getByRole("button", { name: "Pause", exact: true }).click();
  await page.getByLabel("Disable auto rewind").uncheck();
  await choose(page, "Jump forwards time", "10 sec");
});

test("seeking from the system media controls can be turned off", async ({ page }) => {
  await page.addInitScript(() => {
    const registered = new Set<string>();
    Object.assign(window, { mediaActions: registered });
    const original = navigator.mediaSession.setActionHandler.bind(navigator.mediaSession);
    navigator.mediaSession.setActionHandler = (action, handler) => {
      if (handler) registered.add(action);
      else registered.delete(action);
      original(action, handler);
    };
  });
  const actions = () =>
    page.evaluate(() => [...(window as unknown as { mediaActions: Set<string> }).mediaActions].sort());
  const id = await itemIdByTitle("The Long Tide");
  await signIn(page, accounts.other);
  await page.goto(`/item/${id}`);
  await page.getByRole("button", { name: /^Play/ }).click();
  await expect.poll(actions).toContain("seekto");
  await player(page).getByRole("button", { name: "Pause", exact: true }).click();

  await openSettings(page);
  await page.getByLabel("Allow position seeking on media notification controls").uncheck();
  await expect.poll(actions).not.toContain("seekto");
  expect(await actions()).toEqual(expect.arrayContaining(["pause", "play", "seekbackward", "seekforward"]));
  await page.getByLabel("Allow position seeking on media notification controls").check();
  await expect.poll(actions).toContain("seekto");
});

test("the account section names the server and user, and switching returns to the server list", async ({
  page,
}) => {
  await signIn(page);
  await openSettings(page);
  const account = page.getByRole("region", { name: "Account" });
  await expect(account.getByLabel("Host")).toHaveValue(qa.origin);
  await expect(account.getByLabel("Username")).toHaveValue(accounts.user.username);
  await expect(account).toContainText(`Server version ${qa.serverVersion}`);

  await account.getByRole("button", { name: "Switch Server/User" }).click();
  await expect(page).toHaveURL(/\/connect/);
  await expect(page.getByText(qa.origin)).toBeVisible();
});

test("diagnostics describe this browser and server without any credentials", async ({ page, context }) => {
  await context.grantPermissions(["clipboard-read", "clipboard-write"]);
  await signIn(page);
  await openSettings(page);
  const secrets = await page.evaluate(() =>
    Object.keys(localStorage)
      .map((key) => localStorage.getItem(key) ?? "")
      .flatMap((value) => [...value.matchAll(/"(?:accessToken|refreshToken|token)":"([^"]+)"/g)])
      .map((match) => match[1] ?? ""),
  );
  expect(secrets.length).toBeGreaterThan(0);

  const diagnostics = page.getByRole("region", { name: "Diagnostics" });
  await expect(diagnostics).toContainText(`Server version ${qa.serverVersion}`);
  await expect(diagnostics).toContainText("Browser client");
  await diagnostics.getByRole("button", { name: "Copy" }).click();
  const copied = await page.evaluate(() => navigator.clipboard.readText());
  expect(copied).toContain(qa.origin);
  expect(copied).toContain(`Server version ${qa.serverVersion}`);
  expect(copied).toContain(await page.evaluate(() => navigator.userAgent));
  for (const secret of [...secrets, accounts.user.password]) expect(copied).not.toContain(secret);

  await expect(page.getByRole("region", { name: "Browser limits" })).toContainText("not available here");
});

test("an account allowed to download saves an item's files; other accounts are not offered it", async ({
  page,
}) => {
  const id = await itemIdByTitle("Skyline 1");
  await signIn(page);
  await page.goto(`/item/${id}`);
  const saving = page.waitForEvent("download");
  await page.getByRole("button", { name: "Download" }).click();
  const download = await saving;
  expect(download.suggestedFilename()).toBe("Skyline 1.zip");
  expect(await download.failure()).toBeNull();

  await page.getByRole("button", { name: "Sign out" }).click();
  await signIn(page, accounts.limited);
  await page.goto(`/item/${id}`);
  await expect(page.getByRole("heading", { level: 1, name: "Skyline 1" })).toBeVisible();
  await expect(page.getByRole("button", { name: "Download" })).toHaveCount(0);
});
