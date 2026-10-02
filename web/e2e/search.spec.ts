import { expect, test } from "@playwright/test";
import { accounts, qa, serverApi, signIn } from "./qa";

// The synthetic library's "Catalog Volume" books outnumber the server's default of 12 search results.

test("a search matching more books than the first results can show them all, and keeps them on return", async ({
  page,
}) => {
  const api = await serverApi(accounts.user);
  const { body } = await api.call(`/api/libraries/${qa.libraries.books}/items?limit=0`);
  const matching = (
    body.results as { media: { metadata: { title: string; subtitle: string | null } } }[]
  ).filter(({ media }) => /catalog/i.test(`${media.metadata.title} ${media.metadata.subtitle ?? ""}`)).length;
  expect(matching).toBeGreaterThan(12);

  await signIn(page);
  await page.goto(`/library/${qa.libraries.books}/search`);
  await page.getByRole("searchbox", { name: "Search" }).fill("catalog");
  const results = page.getByRole("list", { name: "Search results" }).getByRole("listitem");
  await expect(results).toHaveCount(12);

  const more = page.getByRole("main").getByRole("link", { name: "More" });
  for (let step = 0; step < 5 && (await more.isVisible()); step++) {
    const shown = await results.count();
    await more.click();
    await expect(results).not.toHaveCount(shown);
  }
  await expect(more).toBeHidden();
  await expect(results).toHaveCount(matching);

  await results.last().getByRole("link").first().click();
  await expect(page).toHaveURL(/\/item\//);
  await page.goBack();
  await expect(results).toHaveCount(matching);
});

test("a new search starts again from the first results", async ({ page }) => {
  await signIn(page);
  await page.goto(`/library/${qa.libraries.books}/search`);
  const box = page.getByRole("searchbox", { name: "Search" });
  await box.fill("catalog");
  const results = page.getByRole("list", { name: "Search results" }).getByRole("listitem");
  await expect(results).toHaveCount(12);
  await page.getByRole("main").getByRole("link", { name: "More" }).click();
  await expect(results).not.toHaveCount(12);

  await box.fill("catalog volume");
  await expect(page).toHaveURL(/q=catalog\+volume/);
  await expect(page).not.toHaveURL(/limit=/);
  await expect(results).toHaveCount(12);
});

test("asking for more from the keyboard continues at the first result it revealed", async ({ page }) => {
  await signIn(page);
  await page.goto(`/library/${qa.libraries.books}/search?q=catalog`);
  const results = page.getByRole("list", { name: "Search results" }).getByRole("listitem");
  await expect(results).toHaveCount(12);

  const more = page.getByRole("main").getByRole("link", { name: "More" });
  for (let step = 0; step < 5 && (await more.isVisible()); step++) {
    const shown = await results.count();
    await more.focus();
    await page.keyboard.press("Enter");
    await expect(results.nth(shown).getByRole("link").first()).toBeFocused();
  }
  await expect(more).toBeHidden();
});

test("asking for more authors from the keyboard continues at the first author it revealed", async ({
  page,
}) => {
  // Thirteen books get authors named by a word no title holds, so only the authors outnumber the first results.
  const api = await serverApi(accounts.admin);
  const { body } = await api.call(`/api/libraries/${qa.libraries.books}/items?limit=0`);
  const ids = (body.results as { id: string; media: { metadata: { title: string } } }[])
    .filter(({ media }) => /catalog/i.test(media.metadata.title))
    .slice(0, 13)
    .map(({ id }) => id);
  // The listing leaves out the authors themselves; each book's own record has them to put back.
  const books: { id: string; authors: { id: string; name: string }[] }[] = [];
  for (const id of ids) {
    const { body: item } = await api.call(`/api/items/${id}`);
    books.push({ id, authors: item.media.metadata.authors });
  }
  const setAuthors = (id: string, authors: { name: string }[]) =>
    api.call(`/api/items/${id}/media`, { method: "PATCH", body: { metadata: { authors } } });
  try {
    for (const [index, book] of books.entries()) {
      await setAuthors(book.id, [{ name: `Quillon Writer ${String(index + 1).padStart(2, "0")}` }]);
    }
    await signIn(page);
    await page.goto(`/library/${qa.libraries.books}/search?q=quillon`);
    const authors = page
      .locator("section", { has: page.getByRole("heading", { name: "Authors", exact: true }) })
      .getByRole("listitem");
    await expect(authors).toHaveCount(12);

    const more = page.getByRole("main").getByRole("link", { name: "More" });
    await more.focus();
    await page.keyboard.press("Enter");
    await expect(authors.nth(12).getByRole("link").first()).toBeFocused();
    await expect(more).toBeHidden();
  } finally {
    for (const book of books) await setAuthors(book.id, book.authors);
  }
});
