import { execFileSync } from "node:child_process";
import { expect, type Page, test } from "@playwright/test";
import { type Account, accounts, itemIdByTitle, serverApi } from "./qa";

// The self-hosted deployment from docs/DEPLOYMENT.md: the production image under /web behind nginx, on the
// server's own origin (qa/deploy.mjs). The browser reaches the proxy on 19882 under a port-less host name.
const origin = "http://abs-web.test";
const web = `${origin}/web`;

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

/** Every request the page makes, by origin, so a journey can show nothing left the deployment's origin. */
function originsOf(page: Page) {
  const seen = new Set<string>();
  page.on("request", (request) => {
    const url = new URL(request.url());
    if (url.protocol.startsWith("http")) seen.add(url.origin);
  });
  return seen;
}

async function chooseServer(page: Page) {
  await page.goto(`${web}/connect`);
  await page.getByLabel("Server address").fill(origin);
  await page.getByRole("button", { name: "Continue" }).click();
}

async function signInHere(page: Page, account: Account) {
  await chooseServer(page);
  await page.getByLabel("Username").fill(account.username);
  await page.getByLabel("Password").fill(account.password);
  await page.getByRole("button", { name: "Sign in", exact: true }).click();
  await expect(page.getByRole("navigation", { name: "Library" })).toBeVisible();
}

test("signing in through the server's OpenID provider returns to the client signed in, and survives a reload", async ({
  page,
}) => {
  await chooseServer(page);
  await page.getByRole("button", { name: "Sign in with QA SSO" }).click();
  await expect(page.getByRole("heading", { name: "QA identity provider" })).toBeVisible();
  await page.getByRole("button", { name: "Continue as QA OpenID" }).click();

  await expect(page.getByRole("navigation", { name: "Library" })).toBeVisible();
  expect(page.url().startsWith(`${web}/`)).toBe(true);
  expect(new URL(page.url()).search).not.toContain("code=");
  const admin = await serverApi(accounts.admin);
  const users: { username: string }[] = (await admin.call("/api/users")).body.users;
  expect(users.map((user) => user.username)).toContain("qa-openid");

  await page.reload();
  await expect(page.getByRole("navigation", { name: "Library" })).toBeVisible();
  await page.getByRole("button", { name: "Sign out" }).click();
  await expect(page).toHaveURL(new RegExp(`^${web}/connect`));
});

test("a refused OpenID sign-in says so and leads back to signing in", async ({ page }) => {
  await chooseServer(page);
  await page.getByRole("button", { name: "Sign in with QA SSO" }).click();
  await page.getByRole("button", { name: "Deny" }).click();

  // 2.30.0 drops the provider's "access_denied" and reports its own failed code exchange instead.
  await expect(page.getByRole("main").getByRole("alert")).toContainText(
    "OpenID sign-in did not complete: the server refused it (Error in callback)",
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
  const response = await request.get("http://127.0.0.1:19883/web/connect");
  expect(response.status()).toBe(200);
  expect(response.headers()["x-powered-by"]).toBeUndefined();
  expect((await request.get("http://127.0.0.1:19883/connect")).status()).toBe(404);
});
