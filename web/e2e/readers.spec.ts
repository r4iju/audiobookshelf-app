import { expect, test } from "@playwright/test";
import { accounts, qa, serverApi, signIn } from "./qa";

type Api = Awaited<ReturnType<typeof serverApi>>;

async function bookId(api: Api, title: string) {
  const { body } = await api.call(
    `/api/libraries/${qa.libraries.books}/search?q=${encodeURIComponent(title)}`,
  );
  return body.book[0].libraryItem.id as string;
}

async function resetProgress(api: Api, itemId: string) {
  const me = (await api.call("/api/me")).body;
  for (const progress of me.mediaProgress) {
    if (progress.libraryItemId === itemId && !progress.episodeId)
      await api.call(`/api/me/progress/${progress.id}`, { method: "DELETE" });
  }
}

const serverProgress = async (api: Api, itemId: string) =>
  (await api.call(`/api/me/progress/${itemId}`)).body;

test("a PDF turns pages and follows its links, and resumes where it was left here and on other clients", async ({
  page,
}) => {
  const api = await serverApi(accounts.user);
  const id = await bookId(api, "Field Guide to Quiet");
  await resetProgress(api, id);

  await signIn(page);
  await page.goto(`/item/${id}`);
  await page.getByRole("link", { name: "Read" }).click();
  await expect(page.getByRole("heading", { level: 1, name: "Field Guide to Quiet" })).toBeVisible();
  await expect(page.getByText("Field Guide to Quiet - Page 1", { exact: true })).toBeVisible();
  await expect(page.getByText("Page 1 of 120")).toBeVisible();

  await page.getByRole("button", { name: "Next page" }).click();
  await expect(page.getByText("Field Guide to Quiet - Page 2", { exact: true })).toBeVisible();
  await page.keyboard.press("ArrowRight");
  await expect(page.getByText("Page 3 of 120")).toBeVisible();
  await expect.poll(async () => (await serverProgress(api, id))?.ebookLocation).toBe("3");
  expect((await serverProgress(api, id)).ebookProgress).toBeCloseTo(2 / 120, 5);

  await page.getByLabel("Go to page").fill("1");
  await page.getByLabel("Go to page").press("Enter");
  await expect(page.getByText("Field Guide to Quiet - Page 1", { exact: true })).toBeVisible();
  await page.getByRole("link", { name: "Jump to page 3" }).click();
  await expect(page.getByText("Field Guide to Quiet - Page 3", { exact: true })).toBeVisible();
  await expect.poll(async () => (await serverProgress(api, id))?.ebookLocation).toBe("3");

  await page.reload();
  await expect(page.getByText("Field Guide to Quiet - Page 3", { exact: true })).toBeVisible();

  // Another client moved on; opening the book again follows it.
  await api.call(`/api/me/progress/${id}`, {
    method: "PATCH",
    body: { ebookLocation: "40", ebookProgress: 39 / 120 },
  });
  await page.goto(`/item/${id}`);
  await page.getByRole("link", { name: "Read" }).click();
  await expect(page.getByText("Field Guide to Quiet - Page 40", { exact: true })).toBeVisible();
  await page.getByRole("link", { name: "Back" }).click();
  await expect(page.getByRole("heading", { level: 1, name: "Field Guide to Quiet" })).toBeVisible();
});

test("reading a book's PDF while its audio plays keeps both positions", async ({ page }) => {
  const api = await serverApi(accounts.user);
  const id = await bookId(api, "The Long Tide");
  await resetProgress(api, id);

  await signIn(page);
  await page.goto(`/item/${id}`);
  await page.getByRole("main").getByRole("button", { name: "Play", exact: true }).click();
  const player = page.getByRole("region", { name: "Player" });
  await expect(player.getByRole("button", { name: "Pause", exact: true })).toBeVisible();
  await page.getByRole("link", { name: "Read" }).click();
  await expect(page.getByText("The Long Tide Companion - Page 1", { exact: true })).toBeVisible();
  await page.getByRole("button", { name: "Next page" }).click();
  await expect(page.getByText("Page 2 of 12")).toBeVisible();
  await expect(player.getByRole("button", { name: "Pause", exact: true })).toBeVisible();

  await expect
    .poll(
      async () => {
        const progress = await serverProgress(api, id);
        return progress?.ebookLocation === "2" && progress.currentTime > 2;
      },
      { timeout: 30_000 },
    )
    .toBe(true);
  await player.getByRole("button", { name: "Pause", exact: true }).click();
});

test("a document the server cannot deliver is reported, with a way back", async ({ page }) => {
  const api = await serverApi(accounts.user);
  const id = await bookId(api, "Field Guide to Quiet");
  await signIn(page);
  await page.route(`**/api/items/${id}/ebook**`, (route) =>
    route.fulfill({ status: 404, body: "Not Found" }),
  );
  await page.goto(`/read/${id}`);
  await expect(page.getByRole("main").getByRole("alert")).toContainText("Not found");
  await expect(page.getByRole("link", { name: "Back" })).toBeVisible();

  await page.unroute(`**/api/items/${id}/ebook**`);
  await page.route(`**/api/items/${id}/ebook**`, (route) =>
    route.fulfill({ status: 200, contentType: "application/pdf", body: "this is not a pdf" }),
  );
  await page.reload();
  await expect(page.getByRole("main").getByRole("alert")).toContainText("could not be opened");
});
