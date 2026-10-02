import { readdirSync, readFileSync, rmSync } from "node:fs";
import { join } from "node:path";
import { expect, test } from "@playwright/test";
import { accounts, itemIdByTitle, qa, serverApi, signIn } from "./qa";

const mailDir = join(import.meta.dirname, "..", "qa", ".runtime", "mail");
const sentMail = () =>
  readdirSync(mailDir, { withFileTypes: true })
    .filter((entry) => entry.name.endsWith(".json"))
    .map(
      (entry) =>
        JSON.parse(readFileSync(join(mailDir, entry.name), "utf8")) as { to: string[]; data: string },
    );

test("an administrator opens an item's RSS feed, listeners see its address, and closing it takes it down", async ({
  page,
  browser,
}) => {
  const admin = await serverApi(accounts.admin);
  const id = await itemIdByTitle("The Long Tide");
  const openFeeds = async () =>
    (
      (await admin.call("/api/feeds")).body.feeds as { id: string; entityId: string; feedUrl: string }[]
    ).filter((feed) => feed.entityId === id);
  for (const feed of await openFeeds()) await admin.call(`/api/feeds/${feed.id}/close`, { method: "POST" });
  const slug = `qa-long-tide-${Date.now()}`;

  await signIn(page, accounts.admin);
  await page.goto(`/item/${id}`);
  await page.getByRole("button", { name: "Open RSS Feed" }).click();
  const dialog = page.getByRole("dialog", { name: "Open RSS Feed" });
  await dialog.getByLabel("RSS Feed Slug").fill(slug);
  await expect(dialog).toContainText(`Feed URL will be ${qa.origin}/feed/${slug}`);
  await expect(dialog).toContainText("Most podcast apps will require the RSS feed URL is using HTTPS");
  await expect(dialog.getByLabel("Prevent Indexing")).toBeChecked();
  await dialog.getByLabel("Custom owner Name").fill("QA Owner");
  await dialog.getByRole("button", { name: "Open Feed" }).click();

  const open = page.getByRole("dialog", { name: "RSS Feed is Open" });
  await expect(open.getByRole("textbox", { name: "RSS Feed" })).toHaveValue(`${qa.origin}/feed/${slug}`);
  await expect(open).toContainText("QA Owner");
  expect((await openFeeds()).map((feed) => feed.feedUrl)).toEqual([`/feed/${slug}`]);
  const xml = await (await fetch(`${qa.origin}/feed/${slug}`)).text();
  expect(xml).toContain("The Long Tide");
  await open.getByRole("button", { name: "Close", exact: true }).click();

  // A listener sees the open feed's address but cannot close it, and items without one show nothing.
  const listener = await browser.newPage();
  await signIn(listener, accounts.user);
  await listener.goto(`/item/${id}`);
  await listener.getByRole("button", { name: "RSS Feed", exact: true }).click();
  const shown = listener.getByRole("dialog", { name: "RSS Feed is Open" });
  await expect(shown.getByRole("textbox", { name: "RSS Feed" })).toHaveValue(`${qa.origin}/feed/${slug}`);
  await expect(shown.getByRole("button", { name: "Close Feed" })).toHaveCount(0);
  await listener.goto(`/item/${await itemIdByTitle("Salt and Signal")}`);
  await expect(listener.getByRole("heading", { level: 1, name: "Salt and Signal" })).toBeVisible();
  await expect(listener.getByRole("button", { name: /RSS Feed/ })).toHaveCount(0);
  await listener.close();

  await page.reload();
  await page.getByRole("button", { name: "RSS Feed", exact: true }).click();
  await page.getByRole("dialog").getByRole("button", { name: "Close Feed" }).click();
  await expect(page.getByRole("main").getByRole("status")).toContainText("RSS feed closed");
  await expect.poll(openFeeds).toEqual([]);
  expect((await fetch(`${qa.origin}/feed/${slug}`)).status).toBe(404);
  await expect(page.getByRole("button", { name: "Open RSS Feed" })).toBeVisible();
});

test("an ebook is sent to an e-reader the account may use, and a failed delivery says so", async ({
  page,
}) => {
  const admin = await serverApi(accounts.admin);
  // The sink shares the server's loopback. Not by the fixtures' name: the server's mailer looks names up in DNS, which
  // answers with the VM's host gateway, the route qa/server.mjs keeps fixture traffic off because it drops connections.
  await admin.call("/api/emails/settings", {
    method: "PATCH",
    body: { host: "127.0.0.1", port: 19886, secure: false, fromAddress: "abs-qa@example.invalid" },
  });
  await admin.call("/api/emails/ereader-devices", {
    method: "POST",
    body: {
      ereaderDevices: [
        { name: "QA Reader", email: "reader@example.invalid", availabilityOption: "userOrUp", users: [] },
        {
          name: "Bouncing Reader",
          email: "reader@bounce.invalid",
          availabilityOption: "userOrUp",
          users: [],
        },
        {
          name: "Admin Reader",
          email: "admin-reader@example.invalid",
          availabilityOption: "adminOrUp",
          users: [],
        },
      ],
    },
  });
  rmSync(mailDir, { recursive: true, force: true });

  await signIn(page, accounts.user);
  await page.goto(`/item/${await itemIdByTitle("Paper Lanterns")}`);
  await page.getByRole("button", { name: "Send Ebook to Device" }).click();
  const dialog = page.getByRole("dialog", { name: "Select a device" });
  await expect(dialog.getByRole("button", { name: "Admin Reader" })).toHaveCount(0);
  await dialog.getByRole("button", { name: "QA Reader" }).click();
  await expect(page.getByRole("main").getByRole("status")).toContainText("Ebook sent to QA Reader");
  await expect.poll(() => sentMail().length).toBe(1);
  const [mail] = sentMail();
  expect(mail?.to).toEqual(["<reader@example.invalid>"]);
  expect(mail?.data).toContain('filename="Paper Lanterns.epub"');

  await page.getByRole("button", { name: "Send Ebook to Device" }).click();
  await page
    .getByRole("dialog", { name: "Select a device" })
    .getByRole("button", { name: "Bouncing Reader" })
    .click();
  await expect(page.getByRole("main").getByRole("alert")).toContainText("Failed to send ebook to device");
  expect(sentMail()).toHaveLength(1);

  // Audiobooks without an ebook have nothing to send.
  await page.goto(`/item/${await itemIdByTitle("Salt and Signal")}`);
  await expect(page.getByRole("heading", { level: 1, name: "Salt and Signal" })).toBeVisible();
  await expect(page.getByRole("button", { name: "Send Ebook to Device" })).toHaveCount(0);
});
