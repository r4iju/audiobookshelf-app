import { expect, type Page, test } from "@playwright/test";
import { qa, signIn } from "./qa";

const grid = (page: Page) => page.getByRole("list", { name: "Library items" });

test("sort, filter and page live in the address and survive a reload", async ({ page }) => {
  await signIn(page);
  await page.goto(`/library/${qa.libraries.books}/items`);
  await expect(page.getByRole("heading", { level: 1, name: "Audiobooks" })).toBeVisible();

  await page.getByLabel("Sort by").selectOption({ label: "Title" });
  await expect(page).toHaveURL(/sort=media\.metadata\.title/);
  await expect(grid(page).getByRole("link").first()).toContainText("A Very Long Story Title");

  await page.getByRole("button", { name: "Descending" }).click();
  await expect(page).toHaveURL(/desc=1/);
  await expect(grid(page).getByRole("link").first()).toContainText("The Long Tide");

  await page.getByRole("link", { name: "Next" }).click();
  await expect(page).toHaveURL(/page=2/);
  await page.reload();
  await expect(page.getByText(/Page 2 of \d+/)).toBeVisible();
  await expect(page.getByLabel("Sort by")).toHaveValue("media.metadata.title");
  await expect(grid(page).getByRole("link").first()).not.toContainText("The Long Tide");

  await page.getByLabel("Filter").selectOption({ label: "Harbor Lights" });
  await expect(page).toHaveURL(/filter=series\./);
  await expect(page).not.toHaveURL(/page=2/);
  await expect(grid(page).getByRole("link")).toHaveCount(2);
  await expect(grid(page)).toContainText("Salt and Signal");
});

test("cards keep one height whether or not a book has a cover or a long title", async ({ page }) => {
  await signIn(page);
  await page.goto(`/library/${qa.libraries.books}/items?sort=media.metadata.title`);
  const cards = grid(page).getByRole("link");
  await expect(cards.first()).toContainText("A Very Long Story Title");
  await expect(cards.first()).toContainText("No cover");
  const heights = await cards.evaluateAll((links) =>
    links.slice(0, 8).map((link) => Math.round(link.getBoundingClientRect().height)),
  );
  expect(new Set(heights).size).toBe(1);
});

test("search leads to a book, its series and its author", async ({ page }) => {
  await signIn(page);
  await page.goto(`/library/${qa.libraries.books}/search`);
  await page.getByRole("searchbox", { name: "Search" }).fill("long tide");
  await page.getByRole("link", { name: /^The Long Tide/ }).click();

  await expect(page.getByRole("heading", { level: 1, name: "The Long Tide" })).toBeVisible();
  await expect(page.getByRole("button", { name: /^Play/ })).toBeVisible();
  await expect(page.getByRole("link", { name: "Read" })).toBeVisible();
  const chapters = page.getByRole("region", { name: "Chapters" });
  await expect(chapters.getByRole("listitem")).toHaveCount(3);

  await page.getByRole("link", { name: "Harbor Lights #1" }).click();
  await expect(page.getByRole("heading", { level: 1, name: "Harbor Lights" })).toBeVisible();
  const books = page.getByRole("list", { name: "Library items" }).getByRole("link");
  await expect(books).toHaveCount(2);
  await expect(books.first()).toContainText("The Long Tide");
  await books.first().click();
  await expect(page.getByRole("heading", { level: 1, name: "The Long Tide" })).toBeVisible();

  await page.getByRole("link", { name: "Mira Vale" }).click();
  await expect(page.getByRole("heading", { level: 1, name: "Mira Vale" })).toBeVisible();
  await expect(page.getByRole("main")).toContainText("Salt and Signal");
});

test("an item that does not exist says so instead of a blank page", async ({ page }) => {
  await signIn(page);
  await page.goto("/item/li_does_not_exist");
  await expect(page.getByRole("main").getByRole("alert")).toContainText(/not found/i);
});

test("the keyboard can skip straight to the content", async ({ page }) => {
  await signIn(page);
  await page.goto(`/library/${qa.libraries.books}`);
  await expect(page.getByRole("heading", { level: 1, name: "Audiobooks" })).toBeVisible();
  await page.keyboard.press("Tab");
  await expect(page.getByRole("link", { name: "Skip to content" })).toBeFocused();
  await page.keyboard.press("Enter");
  await expect(page.getByRole("main")).toBeFocused();
});
