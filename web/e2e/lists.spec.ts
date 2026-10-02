import { expect, type Page, test } from "@playwright/test";
import { accounts, choose, clearProgress, itemIdByTitle, qa, serverApi, signIn } from "./qa";

type Api = Awaited<ReturnType<typeof serverApi>>;

async function deletePlaylists(api: Api) {
  const { body } = await api.call("/api/playlists");
  for (const playlist of body.playlists)
    await api.call(`/api/playlists/${playlist.id}`, { method: "DELETE" });
}

async function deleteCollections() {
  const admin = await serverApi(accounts.admin);
  const { body } = await admin.call("/api/collections");
  for (const collection of body.collections)
    await admin.call(`/api/collections/${collection.id}`, { method: "DELETE" });
}

const titlesIn = (page: Page, list: string) =>
  page.getByRole("list", { name: list }).getByRole("heading").allTextContents();

test("a playlist is built from item pages, plays the next unfinished item and is emptied", async ({
  page,
}) => {
  const api = await serverApi(accounts.user);
  await deletePlaylists(api);
  const salt = await itemIdByTitle("Salt and Signal");
  const tide = await itemIdByTitle("The Long Tide");
  await clearProgress(api, tide);
  await api.call(`/api/me/progress/${salt}`, { method: "PATCH", body: { isFinished: true } });

  await signIn(page);
  await page.goto(`/item/${salt}`);
  await page.getByRole("button", { name: "Add to Playlist" }).click();
  const dialog = page.getByRole("dialog", { name: "Add to Playlist" });
  await dialog.getByLabel("New playlist").fill("Commute");
  await dialog.getByRole("button", { name: "Create" }).click();
  await expect(dialog.getByRole("button", { name: "Remove from Commute" })).toBeVisible();
  await dialog.getByRole("button", { name: "Close" }).click();

  await page.goto(`/item/${tide}`);
  await page.getByRole("button", { name: "Add to Playlist" }).click();
  await dialog.getByRole("button", { name: "Add to Commute" }).click();
  await expect(dialog.getByRole("button", { name: "Remove from Commute" })).toBeVisible();
  await dialog.getByRole("button", { name: "Close" }).click();

  await page.getByRole("navigation", { name: "Main" }).getByRole("link", { name: "Playlists" }).click();
  await page.getByRole("link", { name: "Commute" }).click();
  await expect(page.getByRole("heading", { level: 1, name: "Commute" })).toBeVisible();
  await expect.poll(() => titlesIn(page, "Playlist Items")).toEqual(["Salt and Signal", "The Long Tide"]);

  await page.getByRole("button", { name: "Play", exact: true }).click();
  const player = page.getByRole("region", { name: "Player" });
  await expect(player.getByText("The Long Tide")).toBeVisible();
  await player.getByRole("button", { name: "Pause", exact: true }).click();

  const playlistId = page.url().split("/").pop() as string;
  await page.getByRole("button", { name: "Remove The Long Tide from playlist" }).click();
  await expect.poll(() => titlesIn(page, "Playlist Items")).toEqual(["Salt and Signal"]);
  expect((await api.call(`/api/playlists/${playlistId}`)).body.items).toHaveLength(1);

  // The server deletes a playlist when its last item is removed.
  await page.getByRole("button", { name: "Remove Salt and Signal from playlist" }).click();
  await expect(page.getByText("You have no playlists")).toBeVisible();
  expect((await api.call(`/api/playlists/${playlistId}`)).status).toBe(404);
});

test("podcast episodes keep their identity in playlists", async ({ page }) => {
  const api = await serverApi(accounts.user);
  await deletePlaylists(api);
  const search = await api.call(`/api/libraries/${qa.libraries.podcasts}/search?q=Evening`);
  const podcastId: string = search.body.podcast[0].libraryItem.id;

  await signIn(page);
  await page.goto(`/item/${podcastId}`);
  const episodes = page.getByRole("region", { name: "Episodes" });
  await choose(episodes, "Filter", "All");
  await episodes.getByRole("button", { name: "Add Episode 2: Evening 2 to playlist" }).click();
  const dialog = page.getByRole("dialog", { name: "Add to Playlist" });
  await dialog.getByLabel("New playlist").fill("Evening queue");
  await dialog.getByRole("button", { name: "Create" }).click();
  await expect(dialog.getByRole("button", { name: "Remove from Evening queue" })).toBeVisible();
  await dialog.getByRole("button", { name: "Close" }).click();

  const { body } = await api.call("/api/playlists");
  expect(body.playlists[0].items).toEqual([
    expect.objectContaining({ libraryItemId: podcastId, episodeId: expect.any(String) }),
  ]);
  await page.goto(`/playlist/${body.playlists[0].id}`);
  await expect.poll(() => titlesIn(page, "Playlist Items")).toEqual(["Episode 2: Evening 2"]);
  await page.getByRole("button", { name: "Play Episode 2: Evening 2" }).click();
  await expect(page.getByRole("region", { name: "Player" }).getByText("Episode 2: Evening 2")).toBeVisible();
});

test("collections follow the account's permissions", async ({ page, browser }) => {
  await deleteCollections();
  const api = await serverApi(accounts.user);
  const salt = await itemIdByTitle("Salt and Signal");
  const tide = await itemIdByTitle("The Long Tide");
  await clearProgress(api, salt);
  await clearProgress(api, tide);

  await signIn(page);
  await page.goto(`/item/${salt}`);
  await page.getByRole("button", { name: "Add to Collection" }).click();
  const dialog = page.getByRole("dialog", { name: "Add to Collection" });
  await dialog.getByLabel("New collection").fill("Harbor favourites");
  await dialog.getByRole("button", { name: "Create" }).click();
  await expect(dialog.getByRole("button", { name: "Remove from Harbor favourites" })).toBeVisible();
  await dialog.getByRole("button", { name: "Close" }).click();
  await page.goto(`/item/${tide}`);
  await page.getByRole("button", { name: "Add to Collection" }).click();
  await dialog.getByRole("button", { name: "Add to Harbor favourites" }).click();
  await dialog.getByRole("button", { name: "Close" }).click();

  await page.getByRole("navigation", { name: "Main" }).getByRole("link", { name: "Collections" }).click();
  await page.getByRole("link", { name: "Harbor favourites" }).click();
  await expect(page.getByRole("heading", { level: 1, name: "Harbor favourites" })).toBeVisible();
  await expect.poll(() => titlesIn(page, "Collection Items")).toEqual(["Salt and Signal", "The Long Tide"]);
  // This account may update but not delete.
  await expect(page.getByRole("button", { name: "Delete" })).toHaveCount(0);

  await page.getByRole("button", { name: "Play", exact: true }).click();
  await expect(page.getByRole("region", { name: "Player" }).getByText("Salt and Signal")).toBeVisible();
  await page
    .getByRole("region", { name: "Player" })
    .getByRole("button", { name: "Pause", exact: true })
    .click();

  await page.getByRole("button", { name: "Remove The Long Tide from collection" }).click();
  await expect.poll(() => titlesIn(page, "Collection Items")).toEqual(["Salt and Signal"]);
  const collections = (await (await serverApi(accounts.admin)).call("/api/collections")).body.collections;
  expect(collections[0].books.map((book: { id: string }) => book.id)).toEqual([salt]);

  const limitedContext = await browser.newContext();
  const limited = await limitedContext.newPage();
  await signIn(limited, accounts.limited);
  await limited.goto(`/library/${qa.libraries.books}/collections`);
  await limited.getByRole("link", { name: "Harbor favourites" }).click();
  await expect(limited.getByRole("heading", { level: 1, name: "Harbor favourites" })).toBeVisible();
  await expect(limited.getByRole("button", { name: "Remove Salt and Signal from collection" })).toHaveCount(
    0,
  );
  await limited.goto(`/item/${salt}`);
  await expect(limited.getByRole("heading", { level: 1, name: "Salt and Signal" })).toBeVisible();
  await expect(limited.getByRole("button", { name: "Add to Playlist" })).toBeVisible();
  await expect(limited.getByRole("button", { name: "Add to Collection" })).toHaveCount(0);
  await limitedContext.close();
});

test("on a phone, every section of the library stays reachable", async ({ page }) => {
  await page.setViewportSize({ width: 390, height: 844 });
  await signIn(page);
  await page.goto(`/library/${qa.libraries.books}`);
  const more = page.getByRole("navigation", { name: "More" });
  for (const section of ["Authors", "Collections", "Playlists"])
    await expect(more.getByRole("link", { name: section })).toBeVisible();
  await more.getByRole("link", { name: "Playlists" }).click();
  await expect(page.getByRole("heading", { level: 1, name: "Playlists" })).toBeVisible();
});
