import { expect, test } from "@playwright/test";
import { accounts, itemIdByTitle, serverApi, signIn } from "./qa";

const describe = async (title: string, description: string) => {
  const admin = await serverApi(accounts.admin);
  const id = await itemIdByTitle(title);
  await admin.call(`/api/items/${id}/media`, { method: "PATCH", body: { metadata: { description } } });
  return id;
};

test("a short description that runs past six lines can still be read in full", async ({ page }) => {
  const id = await describe(
    "Catalog Volume 07",
    [
      "Part one.",
      "A keeper of the lighthouse records every passing ship.",
      "Part two.",
      "The ledger runs out of pages in midwinter.",
      "Part three.",
      "A stranger arrives with a second ledger.",
      "Part four.",
      "The two records disagree about one ship.",
      "Part five.",
      "The keeper sails out to find it.",
    ].join("\n"),
  );
  const single = await describe("Catalog Volume 08", "One line about the eighth volume.");

  await signIn(page);
  await page.goto(`/item/${id}`);
  const text = page.getByText("The keeper sails out to find it.");
  const clamped = () => text.evaluate((node) => node.scrollHeight > node.clientHeight);
  await expect.poll(clamped).toBe(true);
  const toggle = page.getByRole("button", { name: "Read more" });
  await expect(toggle).toHaveAttribute("aria-expanded", "false");
  await toggle.click();
  await expect(page.getByRole("button", { name: "Read less" })).toHaveAttribute("aria-expanded", "true");
  expect(await clamped()).toBe(false);

  await page.goto(`/item/${single}`);
  await expect(page.getByText("One line about the eighth volume.")).toBeVisible();
  await expect(page.getByRole("button", { name: /Read (more|less)/ })).toHaveCount(0);
});
