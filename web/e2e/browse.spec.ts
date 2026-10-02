import { expect, type Page, test } from "@playwright/test";
import { accounts, qa, serverApi, signIn } from "./qa";

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

test("in a translated language, navigation, sorting, paging and search use the server interface's translations", async ({
  page,
}) => {
  await signIn(page);
  await page.getByRole("link", { name: "Settings", exact: true }).click();
  await page.getByLabel("Language").selectOption("de");
  await expect(page.locator("html")).toHaveAttribute("lang", "de");
  await expect(page.getByLabel("Sprache").locator('option[value=""]')).toHaveText("Standard-Server-Sprache");
  await expect(page.getByRole("navigation", { name: "Bibliothek" })).toBeVisible();
  await expect(page.getByRole("link", { name: "Statistiken" })).toBeVisible();
  await expect(page.getByRole("button", { name: "Abmelden" })).toBeVisible();

  await page.goto(`/library/${qa.libraries.books}/items`);
  await page.getByRole("button", { name: "Aufsteigend" }).click();
  await expect(page.getByRole("button", { name: "Aufsteigend" })).toHaveAttribute("aria-pressed", "true");
  await expect(page.getByRole("button", { name: "Absteigend" })).toHaveAttribute("aria-pressed", "false");
  await page.getByRole("link", { name: "Vor", exact: true }).click();
  await expect(page.getByText(/^Seite 2 von \d+$/)).toBeVisible();

  await page.goto(`/library/${qa.libraries.books}/search`);
  await expect(page.getByRole("searchbox")).toHaveAttribute("placeholder", "Suche...");
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

test("a series longer than one page shows all its books, page by page in order", async ({ page }) => {
  const admin = await serverApi(accounts.admin);
  const { body } = await admin.call(`/api/libraries/${qa.libraries.books}/items?limit=100`);
  const volumes = (body.results as { id: string; media: { metadata: { title: string } } }[])
    .filter((item) => /^Catalog Volume \d+$/.test(item.media.metadata.title))
    .sort((a, b) => a.media.metadata.title.localeCompare(b.media.metadata.title))
    .slice(0, 26);
  const shelve = (series: (index: number) => { name: string; sequence: string }[]) =>
    admin.call("/api/items/batch/update", {
      method: "POST",
      body: volumes.map((volume, index) => ({
        id: volume.id,
        mediaPayload: { metadata: { series: series(index) } },
      })),
    });
  try {
    await shelve((index) => [{ name: "Catalog Shelf", sequence: String(index + 1) }]);
    const list = await admin.call(`/api/libraries/${qa.libraries.books}/series?limit=100`);
    const shelf = (list.body.results as { id: string; name: string }[]).find(
      (series) => series.name === "Catalog Shelf",
    );

    await signIn(page);
    await page.goto(`/library/${qa.libraries.books}/series/${shelf?.id}`);
    await expect(grid(page).getByRole("listitem")).toHaveCount(24);
    await expect(grid(page).getByRole("listitem").first()).toContainText("Catalog Volume 01");
    await page.getByRole("link", { name: "Next" }).click();
    await expect(grid(page).getByRole("listitem")).toHaveCount(2);
    await expect(grid(page).getByRole("listitem").last()).toContainText("Catalog Volume 26");
  } finally {
    await shelve(() => []);
  }
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

test("series can be collapsed into one card each on the bookshelf, and stay collapsed", async ({ page }) => {
  const api = await serverApi(accounts.user);
  const count = async (collapse: boolean) =>
    (await api.call(`/api/libraries/${qa.libraries.books}/items?limit=1&collapseseries=${collapse ? 1 : 0}`))
      .body.total as number;
  const [all, collapsed] = [await count(false), await count(true)];
  expect(collapsed).toBeLessThan(all);

  await signIn(page);
  await page.goto(`/library/${qa.libraries.books}/items`);
  await expect(page.getByText(`${all} items`)).toBeVisible();
  await page.getByLabel("Collapse Series").check();
  await expect(page.getByText(`${collapsed} items`)).toBeVisible();
  const seriesCard = grid(page).locator(`a[href*="/library/${qa.libraries.books}/series/"]`).first();
  await expect(seriesCard).toBeVisible();

  await page.reload();
  await expect(page.getByLabel("Collapse Series")).toBeChecked();
  await expect(page.getByText(`${collapsed} items`)).toBeVisible();
  await page.getByLabel("Collapse Series").uncheck();
  await expect(page.getByText(`${all} items`)).toBeVisible();
});

test("the bookshelf and a series' books can be shown as a list with each book's length, and stay so", async ({
  page,
}) => {
  const api = await serverApi(accounts.user);
  const found = await api.call(
    `/api/libraries/${qa.libraries.books}/search?q=${encodeURIComponent("The Long Tide")}`,
  );
  const tide = found.body.book[0].libraryItem;
  const length = `${Math.floor(tide.media.duration / 60)}m`;
  await signIn(page);
  await page.goto(`/library/${qa.libraries.books}/items?sort=media.metadata.title&desc=1`);
  const first = grid(page).getByRole("link").first();
  await expect(first).toContainText("The Long Tide");
  await expect(first).not.toContainText(length);

  await page.getByRole("button", { name: "List view" }).click();
  await expect(page.getByRole("button", { name: "List view" })).toHaveAttribute("aria-pressed", "true");
  await expect(first).toContainText("The Long Tide");
  await expect(first).toContainText(length);

  await page.reload();
  await expect(grid(page).getByRole("link").first()).toContainText(length);

  const series = (await api.call(`/api/libraries/${qa.libraries.books}/series?limit=100`)).body.results.find(
    (entry: { books: { media: { duration: number } }[] }) =>
      entry.books.length > 1 && entry.books.every((book) => book.media.duration > 0),
  );
  await page.goto(`/library/${qa.libraries.books}/series/${series.id}`);
  await expect(page.getByRole("button", { name: "List view" })).toHaveAttribute("aria-pressed", "true");
  await expect(grid(page).getByRole("link").first()).toContainText(/\d+[hms](?![a-z])/);
  await page.getByRole("button", { name: "List view" }).click();
  await expect(grid(page).getByRole("link").first()).not.toContainText(/\d+[hms](?![a-z])/);
});

test("each page's title names what it shows, after loading it and after moving to it", async ({ page }) => {
  await signIn(page);
  await page.goto(`/library/${qa.libraries.books}/items?sort=media.metadata.title&desc=1`);
  await expect(page).toHaveTitle("Audiobooks · Audiobookshelf");

  await grid(page)
    .getByRole("link", { name: /The Long Tide/ })
    .click();
  await expect(page.getByRole("heading", { level: 1, name: "The Long Tide" })).toBeVisible();
  await expect(page).toHaveTitle("The Long Tide · Audiobookshelf");

  await page.getByRole("link", { name: "Settings" }).click();
  await expect(page).toHaveTitle("Settings · Audiobookshelf");
  await page.reload();
  await expect(page).toHaveTitle("Settings · Audiobookshelf");
});
