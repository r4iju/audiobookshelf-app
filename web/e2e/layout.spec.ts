import { expect, type Locator, type Page, test } from "@playwright/test";
import { accounts, clearProgress, itemIdByTitle, serverApi, signIn } from "./qa";

// "The Long Tide": three 30 s chapters. The library page ends with its pager.

const player = (page: Page) => page.getByRole("region", { name: "Player" });
const phone = { width: 390, height: 844 };

async function play(page: Page) {
  const account = accounts.other;
  const id = await itemIdByTitle("The Long Tide");
  await clearProgress(await serverApi(account), id);
  await signIn(page, account);
  await page.goto(`/item/${id}`);
  await page.getByRole("button", { name: /^Play/ }).click();
  await expect(player(page)).toContainText("The Long Tide");
}

/** The box that scrolls the page: the nearest scrolling ancestor of the main landmark, else the window. */
const pageScroller = (page: Page) =>
  page.locator("#main").evaluate((main) => {
    for (let node = main.parentElement; node; node = node.parentElement) {
      if (/auto|scroll/.test(getComputedStyle(node).overflowY) && node.scrollHeight > node.clientHeight) {
        const box = node.getBoundingClientRect();
        return { top: node.scrollTop, bottom: box.bottom };
      }
    }
    return { top: window.scrollY, bottom: window.innerHeight };
  });

/** Opens the bookshelf from the navigation, a client-side move that keeps the player as it is. */
async function openLibrary(page: Page) {
  await page.getByRole("navigation", { name: "Main" }).getByRole("link", { name: "Library" }).click();
  await expect(pager(page)).toBeVisible();
}

const pager = (page: Page) => page.getByRole("navigation", { name: "Pages" });

const bottomOf = async (locator: Locator) => {
  const box = await locator.boundingBox();
  if (!box) throw new Error("Not rendered");
  return box.y + box.height;
};

test("on a desktop the player's expand button opens and closes its extra controls", async ({ page }) => {
  await play(page);
  const speed = player(page).getByLabel("Playback Speed", { exact: true });
  await expect(speed).toBeHidden();
  const collapsed = (await player(page).boundingBox())?.height ?? 0;

  await player(page).getByRole("button", { name: "Open full player" }).click();
  await expect(speed).toBeVisible();
  expect((await player(page).boundingBox())?.height).toBeGreaterThan(collapsed + 30);

  await player(page).getByRole("button", { name: "Minimize player" }).click();
  await expect(speed).toBeHidden();
  expect((await player(page).boundingBox())?.height).toBe(collapsed);
});

test("the end of a page can be scrolled above the expanded player on a phone", async ({ page }) => {
  await page.setViewportSize(phone);
  await play(page);
  await player(page).getByRole("button", { name: "Open full player" }).click();
  await openLibrary(page);
  const next = pager(page).getByRole("link", { name: /Next/ });
  await next.scrollIntoViewIfNeeded();
  await page.mouse.wheel(0, 5000);
  const dockTop = (await player(page).boundingBox())?.y ?? 0;
  await expect.poll(() => bottomOf(next)).toBeLessThanOrEqual(dockTop);
});

test("the page's scrollbar ends above the player", async ({ page }) => {
  await page.setViewportSize(phone);
  await play(page);
  await openLibrary(page);
  const dockTop = (await player(page).boundingBox())?.y ?? 0;
  expect((await pageScroller(page)).bottom).toBeLessThanOrEqual(dockTop + 1);
});

test("the expanded player on a phone moves between chapters", async ({ page }) => {
  await page.setViewportSize(phone);
  await play(page);
  await player(page).getByRole("button", { name: "Open full player" }).click();
  await player(page).getByRole("button", { name: "Next chapter" }).click();
  await expect
    .poll(() => player(page).getByRole("slider", { name: "Seek" }).inputValue().then(Number), {
      timeout: 15_000,
    })
    .toBeGreaterThan(29);
});

test("going back to a list returns to where it was scrolled", async ({ page }) => {
  await page.setViewportSize(phone);
  await play(page);
  await openLibrary(page);
  await page
    .getByRole("link", { name: /Catalog Volume 10/ })
    .first()
    .scrollIntoViewIfNeeded();
  const before = (await pageScroller(page)).top;
  expect(before).toBeGreaterThan(500);

  await page
    .getByRole("link", { name: /Catalog Volume 10/ })
    .first()
    .click();
  await expect(page).toHaveURL(/\/item\//);
  await page.goBack();
  await expect.poll(async () => Math.abs((await pageScroller(page)).top - before)).toBeLessThan(40);
});

test("page keys scroll the page on arrival and after following a link", async ({ page }) => {
  await page.setViewportSize(phone);
  await signIn(page, accounts.other);
  await openLibrary(page);
  await page.keyboard.press("PageDown");
  await expect.poll(async () => (await pageScroller(page)).top).toBeGreaterThan(200);

  await page
    .getByRole("link", { name: /Catalog Volume/ })
    .first()
    .click();
  await expect(page).toHaveURL(/\/item\//);
  await page.goBack();
  await expect(pager(page)).toBeVisible();
  const before = (await pageScroller(page)).top;
  await page.keyboard.press("PageDown");
  await expect.poll(async () => (await pageScroller(page)).top).toBeGreaterThan(before + 200);
});
