import { expect, type Page, test } from "@playwright/test";
import { accounts, qa, serverApi, signIn, stack } from "./qa";

type Api = Awaited<ReturnType<typeof serverApi>>;

async function eveningStories(api: Api) {
  const { body } = await api.call(`/api/libraries/${qa.libraries.podcasts}/search?q=Evening`);
  const id: string = body.podcast[0].libraryItem.id;
  const item = (await api.call(`/api/items/${id}?expanded=1`)).body;
  const episodes = new Map<string, string>(
    item.media.episodes.map((episode: { title: string; id: string }) => [episode.title, episode.id]),
  );
  return { id, episode: (title: string) => episodes.get(title) as string };
}

async function resetEpisodes(api: Api, itemId: string) {
  const me = (await api.call("/api/me")).body;
  for (const progress of me.mediaProgress) {
    if (progress.libraryItemId === itemId)
      await api.call(`/api/me/progress/${progress.id}`, { method: "DELETE" });
  }
}

const episodeTitles = (page: Page) =>
  page.getByRole("region", { name: "Episodes" }).getByRole("list").getByRole("heading").allTextContents();

test("episodes sort and filter by progress, and an episode plays with its own progress", async ({ page }) => {
  const api = await serverApi(accounts.user);
  const podcast = await eveningStories(api);
  await resetEpisodes(api, podcast.id);
  await api.call(`/api/me/progress/${podcast.id}/${podcast.episode("Episode 2: Evening 2")}`, {
    method: "PATCH",
    body: { isFinished: true },
  });

  await signIn(page);
  await page.goto(`/item/${podcast.id}`);
  await expect(page.getByRole("heading", { level: 1, name: "Evening Stories" })).toBeVisible();
  const episodes = page.getByRole("region", { name: "Episodes" });
  // Episodic podcasts list unfinished episodes, newest first, by default.
  await expect
    .poll(() => episodeTitles(page))
    .toEqual(["Episode 4: Evening 4", "Episode 3: Evening 3", "Episode 1: Evening 1"]);
  await expect(page.getByRole("button", { name: "Find new episodes" })).toHaveCount(0);

  await episodes.getByLabel("Filter").selectOption({ label: "Complete" });
  await expect.poll(() => episodeTitles(page)).toEqual(["Episode 2: Evening 2"]);
  await episodes.getByLabel("Filter").selectOption({ label: "All" });
  await episodes.getByRole("button", { name: "Ascending" }).click();
  await expect
    .poll(() => episodeTitles(page))
    .toEqual([
      "Episode 1: Evening 1",
      "Episode 2: Evening 2",
      "Episode 3: Evening 3",
      "Episode 4: Evening 4",
    ]);
  // The choice is a browser preference, as in the legacy client, so it carries over to the next visit.
  await page.goto(`/item/${podcast.id}`);
  await expect.poll(() => episodeTitles(page)).toHaveLength(4);
  expect((await episodeTitles(page))[0]).toBe("Episode 1: Evening 1");

  const third = podcast.episode("Episode 3: Evening 3");
  await episodes.getByRole("button", { name: "Play Episode 3: Evening 3" }).click();
  const player = page.getByRole("region", { name: "Player" });
  await expect(player.getByText("Episode 3: Evening 3")).toBeVisible();
  await expect
    .poll(async () => (await api.call(`/api/me/progress/${podcast.id}/${third}`)).body?.currentTime ?? 0, {
      timeout: 30_000,
    })
    .toBeGreaterThan(1);
  await player.getByRole("button", { name: "Pause", exact: true }).click();

  await episodes.getByRole("button", { name: "Mark Episode 3: Evening 3 as finished" }).click();
  await expect
    .poll(async () => (await api.call(`/api/me/progress/${podcast.id}/${third}`)).body?.isFinished)
    .toBe(true);
  // The other episodes keep their own progress.
  expect(
    (await api.call(`/api/me/progress/${podcast.id}/${podcast.episode("Episode 4: Evening 4")}`)).status,
  ).toBe(404);
});

test("latest episodes list the newest unfinished episodes across podcasts and play them", async ({
  page,
}) => {
  const api = await serverApi(accounts.user);
  const podcast = await eveningStories(api);
  await resetEpisodes(api, podcast.id);
  await api.call(`/api/me/progress/${podcast.id}/${podcast.episode("Episode 2: Evening 2")}`, {
    method: "PATCH",
    body: { isFinished: true },
  });

  await signIn(page);
  await page.goto(`/library/${qa.libraries.podcasts}`);
  await page.getByRole("navigation", { name: "Main" }).getByRole("link", { name: "Latest" }).click();
  await expect(page.getByRole("heading", { level: 1, name: "Latest episodes" })).toBeVisible();
  const evening = page
    .getByRole("list", { name: "Latest episodes" })
    .getByRole("listitem")
    .filter({ hasText: "Evening Stories" });
  // Newest first; the server leaves out episodes this listener has finished.
  await expect(evening.getByRole("heading")).toHaveText([
    "Episode 4: Evening 4",
    "Episode 3: Evening 3",
    "Episode 1: Evening 1",
  ]);

  await evening.getByRole("button", { name: "Play Episode 4: Evening 4" }).click();
  await expect(page.getByRole("region", { name: "Player" }).getByText("Episode 4: Evening 4")).toBeVisible();
});

test("an administrator adds a podcast from its feed and downloads an episode on the server", async ({
  page,
}) => {
  const admin = await serverApi(accounts.admin);
  const existing = await admin.call(`/api/libraries/${qa.libraries.podcasts}/search?q=QA%20Feed`);
  for (const result of existing.body?.podcast ?? [])
    await admin.call(`/api/items/${result.libraryItem.id}?hard=1`, { method: "DELETE" });

  await signIn(page, accounts.admin);
  await page.goto(`/library/${qa.libraries.podcasts}`);
  await page.getByRole("link", { name: "Add podcast" }).click();
  await page.getByLabel("RSS feed URL").fill(`http://host.docker.internal:${stack.feedPort}/feed.xml`);
  await page.getByRole("button", { name: "Search", exact: true }).click();

  await expect(page.getByLabel("Title")).toHaveValue("QA Feed Show");
  await expect(page.getByLabel("Author")).toHaveValue("QA Feed Studio");
  await page.getByLabel("Folder").selectOption("/podcasts");
  await page.getByRole("button", { name: "Create" }).click();

  await expect(page.getByRole("heading", { level: 1, name: "QA Feed Show" })).toBeVisible();
  await page.getByRole("button", { name: "Find new episodes" }).click();
  const dialog = page.getByRole("dialog", { name: "Episodes" });
  await dialog.getByRole("checkbox", { name: "Feed Episode 2" }).check();
  await dialog.getByRole("button", { name: "Download 1 episode" }).click();
  await expect(dialog).toHaveCount(0);

  const episodes = page.getByRole("region", { name: "Episodes" });
  await expect(episodes.getByRole("heading", { name: "Feed Episode 2" })).toBeVisible({ timeout: 30_000 });
  const created = (await admin.call(`/api/libraries/${qa.libraries.podcasts}/search?q=QA%20Feed`)).body
    .podcast[0].libraryItem;
  expect(created.path).toBe("/podcasts/QA Feed Show");

  await page.getByRole("button", { name: "Find new episodes" }).click();
  await expect(dialog.getByRole("checkbox", { name: "Feed Episode 2" })).toBeDisabled();
});

test("a feed the server cannot read is reported as such", async ({ page }) => {
  await signIn(page, accounts.admin);
  await page.goto(`/library/${qa.libraries.podcasts}/add-podcast`);
  await page.getByLabel("RSS feed URL").fill(`http://host.docker.internal:${stack.feedPort}/missing.xml`);
  await page.getByRole("button", { name: "Search", exact: true }).click();
  await expect(page.getByRole("main").getByRole("alert")).toContainText("could not read this feed");
  await expect(page.getByRole("button", { name: "Create" })).toHaveCount(0);
});

test("an item's page shows its own library's sections", async ({ page }) => {
  const podcast = await eveningStories(await serverApi(accounts.user));
  await signIn(page);
  await page.goto(`/item/${podcast.id}`);
  await expect(page.getByRole("heading", { level: 1, name: "Evening Stories" })).toBeVisible();
  const nav = page.getByRole("navigation", { name: "Main" });
  await expect(nav.getByRole("link", { name: "Latest" })).toBeVisible();
  await expect(
    page.getByRole("navigation", { name: "Library" }).getByRole("link", { name: "Podcasts" }),
  ).toHaveAttribute("aria-current", "true");
});

test("an episode being listened to continues from the home page's Continue Listening", async ({ page }) => {
  const api = await serverApi(accounts.user);
  const podcast = await eveningStories(api);
  await resetEpisodes(api, podcast.id);
  const third = podcast.episode("Episode 3: Evening 3");
  await api.call(`/api/me/progress/${podcast.id}/${third}`, {
    method: "PATCH",
    body: { currentTime: 3, duration: 12, progress: 0.25 },
  });

  await signIn(page);
  await page.goto(`/library/${qa.libraries.podcasts}`);
  await page
    .getByRole("region", { name: "Continue Listening" })
    .getByRole("link", { name: /Episode 3: Evening 3/ })
    .click();
  await expect(page.getByRole("heading", { level: 1, name: "Episode 3: Evening 3" })).toBeVisible();
  await expect(page.getByRole("main").getByRole("progressbar", { name: "Your Progress" })).toHaveAttribute(
    "aria-valuenow",
    "25",
  );
});

test("an episode has its own page with progress, finishing and discarding", async ({ page }) => {
  const api = await serverApi(accounts.user);
  const podcast = await eveningStories(api);
  await resetEpisodes(api, podcast.id);
  const third = podcast.episode("Episode 3: Evening 3");
  await api.call(`/api/me/progress/${podcast.id}/${third}`, {
    method: "PATCH",
    body: { currentTime: 3, duration: 12, progress: 0.25 },
  });

  await signIn(page);
  await page.goto(`/item/${podcast.id}`);
  await page
    .getByRole("region", { name: "Episodes" })
    .getByRole("link", { name: "Episode 3: Evening 3" })
    .click();
  await expect(page.getByRole("heading", { level: 1, name: "Episode 3: Evening 3" })).toBeVisible();
  await expect(page.getByRole("main").getByRole("link", { name: "Evening Stories" })).toBeVisible();
  const main = page.getByRole("main");
  await expect(main.getByRole("progressbar", { name: "Your Progress" })).toHaveAttribute(
    "aria-valuenow",
    "25",
  );
  await expect(page.getByRole("button", { name: "Remove from Server" })).toHaveCount(0);

  await main.getByRole("button", { name: "Mark as finished" }).click();
  await expect
    .poll(async () => (await api.call(`/api/me/progress/${podcast.id}/${third}`)).body?.isFinished)
    .toBe(true);
  await page.reload();
  await expect(main.getByRole("progressbar", { name: "Your Progress" })).toHaveAttribute(
    "aria-valuenow",
    "100",
  );

  await main.getByRole("button", { name: "Discard progress" }).click();
  await page.getByRole("dialog").getByRole("button", { name: "Discard progress" }).click();
  await expect.poll(async () => (await api.call(`/api/me/progress/${podcast.id}/${third}`)).status).toBe(404);
  await expect(main.getByRole("progressbar", { name: "Your Progress" })).toHaveCount(0);

  await main.getByRole("button", { name: "Play", exact: true }).click();
  await expect(page.getByRole("region", { name: "Player" }).getByText("Episode 3: Evening 3")).toBeVisible();
  await page
    .getByRole("region", { name: "Player" })
    .getByRole("button", { name: "Pause", exact: true })
    .click();
});

test("an administrator follows the server's download queue, clears it, and removes an episode", async ({
  page,
}) => {
  test.setTimeout(90_000);
  const admin = await serverApi(accounts.admin);
  const existing = (await admin.call(`/api/libraries/${qa.libraries.podcasts}/search?q=QA%20Slow`)).body
    .podcast;
  for (const result of existing)
    await admin.call(`/api/items/${result.libraryItem.id}?hard=1`, { method: "DELETE" });
  const library = (await admin.call(`/api/libraries/${qa.libraries.podcasts}`)).body;
  const folder = library.folders.find((entry: { fullPath: string }) => entry.fullPath === "/podcasts");
  const created = (
    await admin.call("/api/podcasts", {
      method: "POST",
      body: {
        libraryId: qa.libraries.podcasts,
        folderId: folder.id,
        path: "/podcasts/QA Slow Show",
        media: {
          metadata: {
            title: "QA Slow Show",
            feedUrl: `http://host.docker.internal:${stack.feedPort}/slow/feed.xml`,
          },
          autoDownloadEpisodes: false,
        },
      },
    })
  ).body;

  await signIn(page, accounts.admin);
  await page.goto(`/item/${created.id}`);
  await page.getByRole("button", { name: "Find new episodes" }).click();
  const dialog = page.getByRole("dialog", { name: "Episodes" });
  await dialog.getByRole("checkbox", { name: "Feed Episode 1" }).check();
  await dialog.getByRole("checkbox", { name: "Feed Episode 2" }).check();
  await dialog.getByRole("button", { name: "Download 2 episodes" }).click();

  const episodes = page.getByRole("region", { name: "Episodes" });
  await expect(episodes.getByText("Downloading episode")).toBeVisible();
  await expect(episodes.getByText("1 Episode(s) queued for download")).toBeVisible();
  await episodes.getByRole("button", { name: "Clear download queue" }).click();
  await page.getByRole("dialog").getByRole("button", { name: "Clear download queue" }).click();
  await expect(episodes.getByText(/queued for download/)).toHaveCount(0);
  await expect(episodes.getByText("Downloading episode")).toHaveCount(0, { timeout: 30_000 });
  await expect(episodes.getByRole("list").getByRole("heading")).toHaveCount(1);
  expect((await admin.call(`/api/items/${created.id}`)).body.media.episodes).toHaveLength(1);

  const [title] = await episodes.getByRole("list").getByRole("heading").allTextContents();
  await episodes.getByRole("link", { name: title }).click();
  await page.getByRole("button", { name: "Remove from Server" }).click();
  await page.getByRole("dialog").getByRole("button", { name: "Remove from Server" }).click();
  await expect(page).toHaveURL(new RegExp(`/item/${created.id}$`));
  await expect
    .poll(async () => (await admin.call(`/api/items/${created.id}`)).body.media.episodes)
    .toHaveLength(0);
});

test("removing an episode returns to its podcast only if its page is still showing", async ({ page }) => {
  test.setTimeout(90_000);
  const admin = await serverApi(accounts.admin);
  const existing = (await admin.call(`/api/libraries/${qa.libraries.podcasts}/search?q=QA%20Remove`)).body
    .podcast;
  for (const result of existing)
    await admin.call(`/api/items/${result.libraryItem.id}?hard=1`, { method: "DELETE" });
  const library = (await admin.call(`/api/libraries/${qa.libraries.podcasts}`)).body;
  const folder = library.folders.find((entry: { fullPath: string }) => entry.fullPath === "/podcasts");
  const created = (
    await admin.call("/api/podcasts", {
      method: "POST",
      body: {
        libraryId: qa.libraries.podcasts,
        folderId: folder.id,
        path: "/podcasts/QA Remove Show",
        media: {
          metadata: {
            title: "QA Remove Show",
            feedUrl: `http://host.docker.internal:${stack.feedPort}/feed.xml`,
          },
          autoDownloadEpisodes: false,
        },
      },
    })
  ).body;

  await signIn(page, accounts.admin);
  await page.goto(`/item/${created.id}`);
  await page.getByRole("button", { name: "Find new episodes" }).click();
  const dialog = page.getByRole("dialog", { name: "Episodes" });
  await dialog.getByRole("checkbox", { name: "Feed Episode 1" }).check();
  await dialog.getByRole("checkbox", { name: "Feed Episode 2" }).check();
  await dialog.getByRole("button", { name: "Download 2 episodes" }).click();
  const episodes = page.getByRole("region", { name: "Episodes" });
  await expect(episodes.getByRole("list").getByRole("heading")).toHaveCount(2, { timeout: 30_000 });

  let release = () => {};
  const released = new Promise<void>((resolve) => {
    release = resolve;
  });
  await page.route(/\/api\/podcasts\/[^/]+\/episode\//, async (route) => {
    await released;
    await route.continue();
  });
  await episodes.getByRole("link", { name: "Feed Episode 1" }).click();
  await page.getByRole("button", { name: "Remove from Server" }).click();
  await page.getByRole("dialog").getByRole("button", { name: "Remove from Server" }).click();
  await page.keyboard.press("Escape");
  await page.getByRole("link", { name: "Settings", exact: true }).click();
  await expect(page).toHaveURL(/\/settings$/);
  const answered = page.waitForResponse(/\/api\/podcasts\/[^/]+\/episode\//);
  release();
  await answered;
  await expect
    .poll(async () => (await admin.call(`/api/items/${created.id}`)).body.media.episodes)
    .toHaveLength(1);
  await page.waitForTimeout(500);
  await expect(page).toHaveURL(/\/settings$/);

  await page.unroute(/\/api\/podcasts\/[^/]+\/episode\//);
  await page.goto(`/item/${created.id}`);
  await episodes.getByRole("link", { name: "Feed Episode 2" }).click();
  await page.getByRole("button", { name: "Remove from Server" }).click();
  await page.getByRole("dialog").getByRole("button", { name: "Remove from Server" }).click();
  await expect(page).toHaveURL(new RegExp(`/item/${created.id}$`));
});
