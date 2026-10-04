import { execFileSync } from "node:child_process";
import { type BrowserContext, expect, type Page, test } from "@playwright/test";
import { type Account, accounts, clearProgress, itemIdByTitle, qa, serverApi } from "./qa";

// The prefixed one-image product on 19882. Plain-HTTP hostname journeys cover browser fallback APIs;
// OpenID uses its exact loopback URL because public authentication callbacks require HTTPS.
const origin = "http://abs-web.test";
const web = `${origin}/web`;
const openIdWeb = "http://127.0.0.1:19882/web";

test.describe.configure({ mode: "serial" });
test.use({
  launchOptions: {
    args: [
      "--autoplay-policy=user-gesture-required",
      "--host-resolver-rules=MAP abs-web.test:80 127.0.0.1:19882",
    ],
  },
});

test.beforeAll(() => {
  test.setTimeout(900_000);
  execFileSync("node", ["qa/deploy.mjs", "up"], { stdio: "inherit" });
});

test.afterAll(() => {
  execFileSync("node", ["qa/deploy.mjs", "down"], { stdio: "inherit" });
});

/** Every request the page makes, by origin, so a journey can show nothing left the deployment's origin. */
function originsOf(page: Page) {
  const seen = new Set<string>();
  page.on("request", (request) => {
    const url = new URL(request.url());
    if (url.protocol.startsWith("http")) seen.add(url.origin);
  });
  return seen;
}

/** The deployment names its own server, so a fresh visit is already at signing in to it. */
async function chooseServer(page: Page, address = web) {
  await page.goto(`${address}/connect`);
  await expect(
    page.getByRole("heading", { level: 1, name: `Sign in to ${new URL(address).host}` }),
  ).toBeVisible();
}

async function signInHere(page: Page, account: Account) {
  await chooseServer(page);
  await page.getByLabel("Username").fill(account.username);
  await page.getByLabel("Password").fill(account.password);
  await page.getByRole("button", { name: "Sign in", exact: true }).click();
  await expect(page.getByRole("navigation", { name: "Library" })).toBeVisible();
}

test("a fresh visit finds the server the client is deployed beside and goes straight to signing in", async ({
  page,
}) => {
  await page.goto(`${web}/connect`);
  await expect(page.getByRole("heading", { level: 1, name: "Sign in to abs-web.test" })).toBeVisible();
  // Browser and backend share the image prefix.
  await expect(page.getByText(`${web} · Server version ${qa.serverVersion}`, { exact: true })).toBeVisible();
  await page.getByLabel("Username").fill(accounts.user.username);
  await page.getByLabel("Password").fill(accounts.user.password);
  await page.getByRole("button", { name: "Sign in", exact: true }).click();
  await expect(page.getByRole("navigation", { name: "Library" })).toBeVisible();
});

test("another server can still be chosen by hand", async ({ page }) => {
  await page.goto(`${web}/connect`);
  await page.getByRole("button", { name: "Change server" }).click();
  const address = page.getByLabel("Server address");
  await expect(address).toHaveValue(web);
  // The QA server answers only its own origin, so the address typed here is checked and found unreachable.
  await address.fill("http://127.0.0.1:19880");
  await page.getByRole("button", { name: "Continue" }).click();
  await expect(page.getByRole("main").getByRole("alert")).toContainText(
    "Could not reach the server at http://127.0.0.1:19880",
  );
});

test("signing in through the server's OpenID provider returns to the client signed in, and survives a reload", async ({
  page,
}) => {
  await chooseServer(page, openIdWeb);
  await page.getByRole("button", { name: "Sign in with QA SSO" }).click();
  await expect(page.getByRole("heading", { name: "QA identity provider" })).toBeVisible();
  await page.getByRole("button", { name: "Continue as QA OpenID" }).click();

  await expect(page.getByRole("navigation", { name: "Library" })).toBeVisible();
  expect(page.url().startsWith(`${openIdWeb}/`)).toBe(true);
  expect(new URL(page.url()).search).not.toContain("code=");
  const admin = await serverApi(accounts.admin);
  const users: { id: string; username: string; type: string }[] = (await admin.call("/api/users")).body.users;
  // The replacement binds issuer/subject to an account and avoids provider-name collisions.
  const signedInUserId = await page.evaluate(() => {
    const registry = JSON.parse(localStorage.getItem("abs-web:v1:connections") ?? "null") as {
      activeId: string;
      connections: { id: string; userId: string }[];
    };
    return registry.connections.find((entry) => entry.id === registry.activeId)?.userId;
  });
  expect(signedInUserId).toBeTruthy();
  expect(Object.values(qa.users)).not.toContain(signedInUserId);
  expect(users.find((user) => user.id === signedInUserId)).toMatchObject({ type: "user" });

  await page.reload();
  await expect(page.getByRole("navigation", { name: "Library" })).toBeVisible();
  await page.getByRole("button", { name: "Sign out" }).click();
  await expect(page).toHaveURL(new RegExp(`^${openIdWeb}/connect`));
});

test("a refused OpenID sign-in says so and leads back to signing in", async ({ page }) => {
  await chooseServer(page, openIdWeb);
  await page.getByRole("button", { name: "Sign in with QA SSO" }).click();
  await page.getByRole("button", { name: "Deny" }).click();

  // The provider refusal is shown without establishing a session.
  await expect(page.getByRole("main").getByRole("alert")).toContainText(
    "OpenID sign-in did not complete: the identity provider refused (access_denied)",
  );
  await page.getByRole("link", { name: "Try again" }).click();
  await expect(page.getByRole("button", { name: "Sign in with QA SSO" })).toBeVisible();
});

test("an OpenID return with no sign-in in progress is not accepted", async ({ page }) => {
  await page.goto(`${web}/oauth?code=forged&state=forged`);
  await expect(page.getByRole("main").getByRole("alert")).toContainText("no sign-in was started in this tab");
  await expect(page.getByRole("navigation", { name: "Library" })).toHaveCount(0);
});

test("pages, deep links, readers and media are all served from the one origin", async ({ page }) => {
  const origins = originsOf(page);
  await signInHere(page, accounts.user);

  const book = await itemIdByTitle("The Long Tide");
  await page.goto(`${web}/item/${book}`);
  await expect(page.getByRole("heading", { level: 1, name: "The Long Tide" })).toBeVisible();
  await page.getByRole("button", { name: /^Play/ }).click();
  const player = page.getByRole("region", { name: "Player" });
  await expect
    .poll(() => player.getByRole("slider", { name: "Seek" }).inputValue().then(Number), { timeout: 15_000 })
    .toBeGreaterThan(1);
  await player.getByRole("button", { name: "Pause", exact: true }).click();

  const comic = await itemIdByTitle("Skyline 1");
  await page.goto(`${web}/read/${comic}`);
  await expect(page.getByText(/Page \d+ of 12/)).toBeVisible();
  const image = page.getByRole("main").getByRole("img", { name: /^Page \d+$/ });
  await expect.poll(() => image.evaluate((element: HTMLImageElement) => element.naturalWidth)).toBe(600);

  const pdf = await itemIdByTitle("Field Guide to Quiet");
  await page.goto(`${web}/read/${pdf}`);
  await expect(page.getByText(/Page \d+ of 120/)).toBeVisible();

  expect([...origins]).toEqual([origin]);
});

test("the production server answers on its own port under the base path, without framework headers", async ({
  request,
}) => {
  const response = await request.get("http://127.0.0.1:19882/web/connect");
  expect(response.status()).toBe(200);
  expect(response.headers()["x-powered-by"]).toBeUndefined();
  expect((await request.get("http://127.0.0.1:19882/connect")).status()).toBe(404);
});

/** Plays a book in a tab for a few seconds from the server's place, pauses, and starts delivering that listening. */
async function listenAndDeliver(page: Page, id: string) {
  await page.goto(`${web}/item/${id}`);
  await page.getByRole("button", { name: /^Play/ }).click();
  const player = page.getByRole("region", { name: "Player" });
  await expect
    .poll(() => player.getByRole("slider", { name: "Seek" }).inputValue().then(Number), { timeout: 15_000 })
    .toBeGreaterThan(42);
  await player.getByRole("button", { name: "Pause", exact: true }).click();
  const sent = page.waitForRequest("**/api/session/local-all");
  await page.evaluate(() => window.dispatchEvent(new Event("online")));
  await sent;
}

async function discardOn(page: Page, id: string) {
  await page.goto(`${web}/item/${id}`);
  await page.getByRole("button", { name: "Discard progress" }).click();
  await page.getByRole("dialog").getByRole("button", { name: "Discard progress" }).click();
}

async function bookAt40() {
  const api = await serverApi(accounts.user);
  const id = await itemIdByTitle("Salt and Signal");
  await clearProgress(api, id);
  await api.call(`/api/me/progress/${id}`, {
    method: "PATCH",
    body: { currentTime: 40, duration: 60, progress: 0.66 },
  });
  return { api, id };
}

// These journeys exercise the client fallback for servers without generation fencing.
// The replacement advertises fencing and can safely finish a reset before an older delivery answers.
async function withoutGenerationFencing(context: BrowserContext) {
  await context.route("**/api/items/*", async (route) => {
    const url = new URL(route.request().url());
    url.host = "127.0.0.1:19882";
    const response = await route.fetch({ url: url.href });
    if (!response.headers()["content-type"]?.includes("application/json")) {
      await route.fulfill({ response });
      return;
    }
    const body = await response.json();
    delete body.progressGeneration;
    delete body.progressGenerations;
    await route.fulfill({ response, json: body });
  });
}

test("on this plain-HTTP origin, a discard waits for listening another tab is sending, and finishes once that tab hears back", async ({
  context,
}) => {
  await withoutGenerationFencing(context);
  const { api, id } = await bookAt40();
  const discarding = await context.newPage();
  await signInHere(discarding, accounts.user);
  expect(await discarding.evaluate(() => "locks" in navigator)).toBe(false);

  // The other tab's listening is held between the browser and the server until the test lets it through.
  const listening = await context.newPage();
  let letThrough = () => {};
  const through = new Promise<void>((resolve) => {
    letThrough = resolve;
  });
  await listening.route("**/api/session/local-all", async (route) => {
    await through;
    await route.continue();
  });
  await listenAndDeliver(listening, id);

  const deletes: string[] = [];
  discarding.on("request", (request) => {
    if (request.method() === "DELETE") deletes.push(request.url());
  });
  await discardOn(discarding, id);
  const status = discarding.getByRole("main").getByRole("status").filter({ hasText: "Discarding progress" });
  await expect(status).toContainText("not confirmed");
  expect(deletes).toEqual([]);

  const answered = listening.waitForResponse("**/api/session/local-all");
  letThrough();
  await answered;
  await discarding.evaluate(() => window.dispatchEvent(new Event("online")));
  await expect(status).toBeHidden();
  expect(deletes).toHaveLength(1);
  expect((await api.call(`/api/me/progress/${id}`)).status).toBe(404);
});

test("on this plain-HTTP origin, listening that failed without an answer leaves keeping or discarding to the user", async ({
  context,
}) => {
  await withoutGenerationFencing(context);
  const { api, id } = await bookAt40();
  const discarding = await context.newPage();
  await signInHere(discarding, accounts.user);
  const listening = await context.newPage();
  await listening.route("**/api/session/local-all", (route) => route.abort("connectionreset"));
  await listenAndDeliver(listening, id);
  await listening.close();

  await discardOn(discarding, id);
  const status = discarding.getByRole("main").getByRole("status").filter({ hasText: "Discarding progress" });
  await expect(status).toContainText("not confirmed");
  await discarding.getByRole("button", { name: "Keep progress" }).click();
  await expect(status).toBeHidden();
  // Kept, not deleted: the server still has its place (this tab may have delivered the other tab's queued listening).
  expect((await api.call(`/api/me/progress/${id}`)).body.currentTime).toBeGreaterThanOrEqual(40);

  await discardOn(discarding, id);
  await expect(status).toContainText("not confirmed");
  await discarding.getByRole("button", { name: "Discard anyway" }).click();
  await expect(status).toBeHidden();
  expect((await api.call(`/api/me/progress/${id}`)).status).toBe(404);
});
