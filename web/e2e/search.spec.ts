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
