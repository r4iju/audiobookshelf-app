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

const book = (page: import("@playwright/test").Page) => page.locator("main iframe").first().contentFrame();

test("an EPUB pages through, jumps by its contents, and resumes at the saved passage here and from other clients", async ({
  page,
}) => {
  const api = await serverApi(accounts.user);
  const id = await bookId(api, "Paper Lanterns");
  await resetProgress(api, id);

  await signIn(page);
  await page.goto(`/item/${id}`);
  await page.getByRole("link", { name: "Read" }).click();
  await expect(page.getByRole("heading", { level: 1, name: "Paper Lanterns" })).toBeVisible();
  await page.getByRole("button", { name: "Next page" }).click();
  await expect(book(page).getByText("Chapter 1: Lantern 1")).toBeInViewport();
  await page.keyboard.press("ArrowRight");
  await expect(book(page).getByText("Chapter 1: Lantern 1")).not.toBeInViewport();
  await expect.poll(async () => (await serverProgress(api, id))?.ebookLocation ?? "").toMatch(/^epubcfi\(/);

  await page.getByRole("button", { name: "Table of Contents" }).click();
  await page.getByRole("dialog").getByRole("button", { name: "Chapter 3: Lantern 3" }).click();
  await expect(book(page).getByRole("heading", { name: "Chapter 3: Lantern 3" })).toBeInViewport();
  await expect.poll(async () => (await serverProgress(api, id))?.ebookProgress ?? 0).toBeGreaterThan(0.2);
  const chapterThree = (await serverProgress(api, id)).ebookLocation as string;

  await page.reload();
  await expect(book(page).getByRole("heading", { name: "Chapter 3: Lantern 3" })).toBeInViewport();

  await page.getByRole("button", { name: "Table of Contents" }).click();
  await page.getByRole("dialog").getByRole("button", { name: "Chapter 5: Lantern 5" }).click();
  await expect(book(page).getByRole("heading", { name: "Chapter 5: Lantern 5" })).toBeInViewport();
  await expect.poll(async () => (await serverProgress(api, id))?.ebookLocation).not.toBe(chapterThree);

  // Another client saved its place in chapter 3; opening the book again follows it.
  await api.call(`/api/me/progress/${id}`, { method: "PATCH", body: { ebookLocation: chapterThree } });
  await page.getByRole("link", { name: "Back" }).click();
  await page.getByRole("link", { name: "Read" }).click();
  await expect(book(page).getByRole("heading", { name: "Chapter 3: Lantern 3" })).toBeInViewport();
});

test("EPUB display settings apply to the text and are kept in this browser", async ({ page }) => {
  const api = await serverApi(accounts.user);
  const id = await bookId(api, "Paper Lanterns");
  await signIn(page);
  await page.goto(`/read/${id}`);
  await expect(book(page).locator("body")).toBeAttached();

  await page.getByRole("button", { name: "Reader settings" }).click();
  const settings = page.getByRole("dialog", { name: "Reader settings" });
  await settings.getByLabel("Theme").selectOption({ label: "Light" });
  await settings.getByLabel("Font family").selectOption({ label: "Sans" });
  await settings.getByLabel("Font scale").fill("150");
  await settings.getByRole("button", { name: "Close" }).click();

  const paragraph = book(page).locator("p").first();
  await expect(paragraph).toHaveCSS("color", "rgb(0, 0, 0)");
  await expect(book(page).locator("body")).toHaveCSS("background-color", "rgb(255, 255, 255)");
  await expect(paragraph).toHaveCSS("font-family", /sans-serif/);

  await page.reload();
  await expect(book(page).locator("body")).toHaveCSS("background-color", "rgb(255, 255, 255)");
  await page.getByRole("button", { name: "Reader settings" }).click();
  await expect(settings.getByLabel("Font scale")).toHaveValue("150");
  await settings.getByLabel("Theme").selectOption({ label: "Dark" });
  await settings.getByLabel("Font family").selectOption({ label: "Serif" });
  await settings.getByLabel("Font scale").fill("100");
});

test("a damaged EPUB is reported as unreadable", async ({ page }) => {
  const api = await serverApi(accounts.user);
  const id = await bookId(api, "Paper Lanterns");
  await signIn(page);
  await page.route(`**/api/items/${id}/ebook**`, (route) =>
    route.fulfill({ status: 200, contentType: "application/epub+zip", body: "PK this is not a zip" }),
  );
  await page.goto(`/read/${id}`);
  await expect(page.getByRole("main").getByRole("alert")).toContainText("could not be opened");
});

for (const { title, format } of [
  { title: "Night Ferry", format: "MOBI" },
  { title: "Glass Orchard", format: "AZW3" },
]) {
  test(`a ${format} book scrolls page by page, jumps by its contents, and resumes at the same passage here and from other clients`, async ({
    page,
  }) => {
    const api = await serverApi(accounts.user);
    const id = await bookId(api, title);
    await resetProgress(api, id);

    await signIn(page);
    await page.goto(`/item/${id}`);
    await page.getByRole("link", { name: "Read" }).click();
    await expect(page.getByRole("heading", { level: 1, name: title })).toBeVisible();
    await expect(book(page).getByText("Chapter 1: Lantern 1")).toBeInViewport();
    await page.getByRole("button", { name: "Next page" }).click();
    await expect(book(page).getByText("Chapter 1: Lantern 1")).not.toBeInViewport();
    await page.getByRole("button", { name: "Previous page" }).click();
    await expect(book(page).getByText("Chapter 1: Lantern 1")).toBeInViewport();

    await page.getByRole("button", { name: "Table of Contents" }).click();
    await page.getByRole("dialog").getByRole("button", { name: "Chapter 3: Lantern 3" }).click();
    await expect(book(page).getByText("Chapter 3: Lantern 3")).toBeInViewport();
    await expect.poll(async () => (await serverProgress(api, id))?.ebookProgress ?? 0).toBeGreaterThan(0.2);
    const atChapterThree = (await serverProgress(api, id)).ebookLocation as string;
    await page.keyboard.press("PageDown");
    await expect(book(page).getByText("Chapter 3: Lantern 3")).not.toBeInViewport();
    await page.waitForTimeout(500);
    const passage = await book(page)
      .locator("p")
      .filter({ visible: true })
      .evaluateAll((paragraphs) => {
        const top = paragraphs.find((p) => p.getBoundingClientRect().top >= 0);
        return top?.textContent?.slice(0, 13) ?? "";
      });
    expect(passage).toMatch(/^Passage 3\.\d+\./);
    await expect.poll(async () => (await serverProgress(api, id))?.ebookLocation ?? "").toMatch(/^mobi:/);
    // The place a page further on, not the one the contents jump saved first.
    await expect.poll(async () => (await serverProgress(api, id))?.ebookLocation).not.toBe(atChapterThree);
    const inChapterThree = (await serverProgress(api, id)).ebookLocation as string;

    await page.reload();
    await expect(book(page).getByText(passage)).toBeInViewport();

    await page.getByRole("button", { name: "Table of Contents" }).click();
    await page.getByRole("dialog").getByRole("button", { name: "Chapter 5: Lantern 5" }).click();
    await expect(book(page).getByText("Chapter 5: Lantern 5")).toBeInViewport();
    await expect.poll(async () => (await serverProgress(api, id))?.ebookLocation).not.toBe(inChapterThree);

    // Another client saved its place in chapter 3; opening the book again follows it.
    await api.call(`/api/me/progress/${id}`, { method: "PATCH", body: { ebookLocation: inChapterThree } });
    await page.getByRole("link", { name: "Back" }).click();
    await page.getByRole("link", { name: "Read" }).click();
    await expect(book(page).getByText(passage)).toBeInViewport();
  });
}

test("MOBI books take the reader's display settings and cannot run scripts", async ({ page }) => {
  const api = await serverApi(accounts.user);
  const id = await bookId(api, "Night Ferry");
  await resetProgress(api, id);
  await signIn(page);
  await page.goto(`/read/${id}`);
  await expect(book(page).getByText("Chapter 1: Lantern 1")).toBeVisible();
  await expect(page.locator("main iframe")).toHaveAttribute("sandbox", "allow-same-origin");

  await page.getByRole("button", { name: "Reader settings" }).click();
  const settings = page.getByRole("dialog", { name: "Reader settings" });
  await settings.getByLabel("Theme").selectOption({ label: "Light" });
  await settings.getByRole("button", { name: "Close" }).click();
  await expect(book(page).locator("p").first()).toHaveCSS("color", "rgb(0, 0, 0)");
  await expect(book(page).locator("body")).toHaveCSS("background-color", "rgb(255, 255, 255)");

  await page.getByRole("button", { name: "Reader settings" }).click();
  await settings.getByLabel("Theme").selectOption({ label: "Dark" });
});

test("a damaged MOBI is reported as unreadable", async ({ page }) => {
  const api = await serverApi(accounts.user);
  const id = await bookId(api, "Night Ferry");
  await signIn(page);
  await page.route(`**/api/items/${id}/ebook**`, (route) =>
    route.fulfill({
      status: 200,
      contentType: "application/x-mobipocket-ebook",
      body: "BOOKMOBI but not really",
    }),
  );
  await page.goto(`/read/${id}`);
  await expect(page.getByRole("main").getByRole("alert")).toContainText("could not be opened");
});

/** Each fixture page is its own colour with a white bar 60px tall per page number (qa/make-library.sh). */
async function shownComicPage(page: import("@playwright/test").Page, number: number) {
  return page
    .getByRole("main")
    .getByRole("img", { name: `Page ${number}`, exact: true })
    .evaluate(async (image) => {
      if (!(image instanceof HTMLImageElement)) return null;
      await image.decode();
      const canvas = document.createElement("canvas");
      canvas.width = image.naturalWidth;
      canvas.height = image.naturalHeight;
      const context = canvas.getContext("2d");
      if (!context) return null;
      context.drawImage(image, 0, 0);
      const pixels = context.getImageData(300, 0, 1, image.naturalHeight).data;
      let bar = 0;
      for (let y = 40; y < image.naturalHeight && (pixels[y * 4 + 1] ?? 0) > 200; y++) bar++;
      return { width: image.naturalWidth, height: image.naturalHeight, number: Math.round(bar / 60) };
    });
}

for (const { issue, format } of [
  { issue: 1, format: "CBZ" },
  { issue: 2, format: "CBR" },
]) {
  test(`a ${format} comic shows its pages in order, and resumes at the saved page here and from other clients`, async ({
    page,
  }) => {
    const api = await serverApi(accounts.user);
    const id = await bookId(api, `Skyline ${issue}`);
    await resetProgress(api, id);

    await signIn(page);
    await page.goto(`/item/${id}`);
    await page.getByRole("link", { name: "Read" }).click();
    await expect(page.getByText("Page 1 of 12")).toBeVisible();
    expect(await shownComicPage(page, 1)).toEqual({ width: 600, height: 900, number: 1 });

    await page.getByRole("button", { name: "Next page" }).click();
    await page.keyboard.press("ArrowRight");
    await expect(page.getByText("Page 3 of 12")).toBeVisible();
    expect((await shownComicPage(page, 3))?.number).toBe(3);
    await expect.poll(async () => (await serverProgress(api, id))?.ebookLocation).toBe("3");
    expect((await serverProgress(api, id)).ebookProgress).toBeCloseTo(2 / 12, 5);

    // Page 10 sorts after page 9 by its number, not between page 1 and page 2 by its name.
    await page.getByRole("button", { name: "Pages" }).click();
    const pages = page.getByRole("dialog", { name: "Pages" });
    await expect(pages.getByRole("button")).toHaveText([
      ...Array.from({ length: 12 }, (_, index) => `page ${index + 1}.png`),
      "Close",
    ]);
    await expect(pages.getByRole("button", { name: "page 3.png" })).toHaveAttribute("aria-current", "page");
    await pages.getByRole("button", { name: "page 10.png" }).click();
    await expect(page.getByText("Page 10 of 12")).toBeVisible();
    expect((await shownComicPage(page, 10))?.number).toBe(10);
    await expect.poll(async () => (await serverProgress(api, id))?.ebookLocation).toBe("10");

    await page.getByRole("button", { name: "Comic details" }).click();
    const details = page.getByRole("dialog", { name: "Comic details" });
    await expect(details.getByRole("definition")).toHaveText([
      `Skyline Issue ${issue}`,
      "Skyline",
      String(issue),
      "Rin Okada",
    ]);
    await expect(details.getByRole("term")).toHaveText(["Title", "Series", "Number", "Writer"]);
    await details.getByRole("button", { name: "Close" }).click();

    await page.reload();
    await expect(page.getByText("Page 10 of 12")).toBeVisible();
    expect((await shownComicPage(page, 10))?.number).toBe(10);

    await api.call(`/api/me/progress/${id}`, {
      method: "PATCH",
      body: { ebookLocation: "6", ebookProgress: 5 / 12 },
    });
    await page.getByRole("link", { name: "Back" }).click();
    await page.getByRole("link", { name: "Read" }).click();
    await expect(page.getByText("Page 6 of 12")).toBeVisible();
    expect((await shownComicPage(page, 6))?.number).toBe(6);
  });
}

test("arrow keys move within an open reader dialog without turning the page behind it", async ({ page }) => {
  const api = await serverApi(accounts.user);
  const id = await bookId(api, "Skyline 1");
  await resetProgress(api, id);
  await signIn(page);
  await page.goto(`/read/${id}`);
  await expect(page.getByText("Page 1 of 12")).toBeVisible();

  await page.getByRole("button", { name: "Pages" }).click();
  await expect(page.getByRole("dialog", { name: "Pages" })).toBeVisible();
  await page.keyboard.press("ArrowRight");
  await page.keyboard.press("PageDown");
  await page.keyboard.press("Escape");
  await expect(page.getByRole("dialog", { name: "Pages" })).toBeHidden();
  await expect(page.getByText("Page 1 of 12")).toBeVisible();
});

test("a damaged comic is reported as unreadable", async ({ page }) => {
  const api = await serverApi(accounts.user);
  const id = await bookId(api, "Skyline 1");
  await signIn(page);
  await page.route(`**/api/items/${id}/ebook**`, (route) =>
    route.fulfill({
      status: 200,
      contentType: "application/vnd.comicbook+zip",
      body: "PK this is not a zip",
    }),
  );
  await page.goto(`/read/${id}`);
  await expect(page.getByRole("main").getByRole("alert")).toContainText("could not be opened");
});
