import { expect, type Locator, type Page, test } from "@playwright/test";
import { accounts, clearProgress, itemIdByTitle, qa, serverApi, signIn } from "./qa";

const player = (page: Page) => page.getByRole("region", { name: "Player" });
const position = (page: Page) => player(page).getByRole("slider", { name: "Seek" }).inputValue().then(Number);
const grid = (page: Page) => page.getByRole("list", { name: "Library items" });

async function playFresh(page: Page) {
  const api = await serverApi(accounts.other);
  const id = await itemIdByTitle("The Long Tide");
  await clearProgress(api, id);
  await signIn(page, accounts.other);
  await page.goto(`/item/${id}`);
  await page.getByRole("button", { name: /^Play/ }).click();
  await expect.poll(() => position(page), { timeout: 15_000 }).toBeGreaterThan(1);
  return { api, id };
}

const verticallyOverlaps = async (a: Locator, b: Locator) => {
  const [boxA, boxB] = [await a.boundingBox(), await b.boundingBox()];
  if (!boxA || !boxB) return false;
  return boxA.y < boxB.y + boxB.height && boxB.y < boxA.y + boxA.height;
};

test("the player's speed and sleep timer are chosen from the app's own list", async ({ page }) => {
  await playFresh(page);
  await player(page).getByRole("button", { name: "Open full player" }).click();

  const speed = player(page).getByRole("combobox", { name: "Playback Speed" });
  await speed.click();
  const speeds = page.getByRole("listbox");
  await expect(speeds).toBeVisible();
  await expect(speeds.getByRole("option", { name: "1×", selected: true })).toBeVisible();
  await speeds.getByRole("option", { name: "1.5×" }).click();
  await expect(speeds).toBeHidden();
  await expect(speed).toHaveText("1.5×");
  await expect(speed).toBeFocused();
  await expect.poll(() => page.evaluate(() => document.querySelector("audio")?.playbackRate)).toBe(1.5);

  const sleep = player(page).getByRole("combobox", { name: "Sleep timer" });
  await sleep.focus();
  await page.keyboard.press("Enter");
  const sleeps = page.getByRole("listbox");
  await expect(sleeps.getByRole("option", { name: "Off", selected: true })).toBeFocused();
  await page.keyboard.press("End");
  await expect(sleeps.getByRole("option", { name: "End of Chapter" })).toBeFocused();
  await page.keyboard.press("Escape");
  await expect(sleeps).toBeHidden();
  await expect(sleep).toHaveText("Off");
  await expect(sleep).toBeFocused();
  await sleep.click();
  await page.getByRole("option", { name: "End of Chapter" }).click();
  await expect(sleep).toHaveText("End of Chapter");
});

test("the bookshelf sort is chosen from the app's own list and orders the books", async ({ page }) => {
  await signIn(page);
  await page.goto(`/library/${qa.libraries.books}/items`);
  const sort = page.getByRole("combobox", { name: "Sort by" });
  await sort.click();
  await page.getByRole("listbox").getByRole("option", { name: "Title" }).click();
  await expect(page).toHaveURL(/sort=media\.metadata\.title/);
  await expect(sort).toHaveText("Title");
  await expect(grid(page).getByRole("link").first()).toContainText("A Very Long Story Title");
});

test("the selected sort direction is shown in words and in the accent colour", async ({ page }) => {
  await signIn(page);
  await page.setViewportSize({ width: 375, height: 800 });
  await page.goto(`/library/${qa.libraries.books}/items`);
  const direction = page.getByRole("group", { name: "Sort direction" });
  const selected = direction.getByRole("button", { pressed: true });
  await expect(selected).toHaveCount(1);
  const shown = (button: Locator) =>
    button.evaluate((node) => {
      const words = [...node.querySelectorAll("span")].find((span) => span.textContent?.trim());
      const probe = document.createElement("span");
      probe.style.color = "var(--accent-strong)";
      document.body.append(probe);
      const accent = getComputedStyle(probe).color;
      probe.remove();
      return {
        wordsWidth: words ? words.getBoundingClientRect().width : 0,
        accentFill: getComputedStyle(node).backgroundColor === accent,
      };
    });

  expect(await shown(selected)).toEqual({ wordsWidth: expect.any(Number), accentFill: true });
  expect((await shown(selected)).wordsWidth).toBeGreaterThan(20);
  const other = direction.getByRole("button", { pressed: false });
  expect((await shown(other)).accentFill).toBe(false);

  await other.click();
  await expect(page).toHaveURL(/desc=/);
  const now = direction.getByRole("button", { pressed: true });
  expect((await shown(now)).accentFill).toBe(true);
  expect((await shown(now)).wordsWidth).toBeGreaterThan(20);
});

test("a book card's own menu plays it or opens its details, by pointer, keyboard or its button", async ({
  page,
}) => {
  const id = await itemIdByTitle("The Long Tide");
  await clearProgress(await serverApi(accounts.user), id);
  await signIn(page);
  await page.goto(`/library/${qa.libraries.books}/items`);
  const card = grid(page).getByRole("link", { name: /The Long Tide/ });

  await card.click({ button: "right" });
  const menu = page.getByRole("menu");
  await expect(menu).toBeVisible();
  await expect(menu.getByRole("menuitem", { name: "Open in new tab" })).toBeVisible();
  await menu.getByRole("menuitem", { name: "Play" }).click();
  await expect(player(page)).toContainText("The Long Tide");
  await expect.poll(() => position(page), { timeout: 15_000 }).toBeGreaterThan(0.5);

  await card.focus();
  await page.keyboard.press("Shift+F10");
  await expect(page.getByRole("menu")).toBeVisible();
  await expect(page.getByRole("menuitem").first()).toBeFocused();
  await page.keyboard.press("Escape");
  await expect(page.getByRole("menu")).toBeHidden();
  await expect(card).toBeFocused();

  await grid(page).getByRole("button", { name: "Actions for The Long Tide" }).click();
  await page.getByRole("menuitem", { name: "Details" }).click();
  await expect(page).toHaveURL(new RegExp(`/item/${id}$`));
});

test("the player closes from its header whether minimized or open, keeping the place listened to", async ({
  page,
}) => {
  const { api, id } = await playFresh(page);
  const close = player(page).getByRole("button", { name: "Close player" });
  const expand = player(page).getByRole("button", { name: "Open full player" });
  await expect(close).toBeVisible();
  expect(await verticallyOverlaps(close, expand)).toBe(true);

  await expand.click();
  const collapse = player(page).getByRole("button", { name: "Minimize player" });
  expect(await verticallyOverlaps(close, collapse)).toBe(true);
  const box = await close.boundingBox();
  expect(Math.min(box?.width ?? 0, box?.height ?? 0)).toBeGreaterThanOrEqual(44);

  await player(page).getByRole("button", { name: "Pause", exact: true }).click();
  const at = await position(page);
  await close.click();
  await expect(player(page)).toBeHidden();
  await expect
    .poll(async () => (await api.call(`/api/me/progress/${id}`)).body?.currentTime ?? 0)
    .toBeCloseTo(at, 0);
});
