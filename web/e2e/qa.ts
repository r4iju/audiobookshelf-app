import { readFileSync } from "node:fs";
import { expect, type Locator, type Page } from "@playwright/test";
import { z } from "zod";

const stateSchema = z.object({
  origin: z.string(),
  serverVersion: z.string(),
  libraries: z.object({ books: z.string(), podcasts: z.string() }),
  users: z.object({ user: z.string(), other: z.string(), limited: z.string() }),
});

export const qa = stateSchema.parse(
  JSON.parse(
    readFileSync(
      new URL(
        `../qa/.runtime/state-${process.env.ABS_QA_CONTAINER ?? "leafwake-web-qa"}.json`,
        import.meta.url,
      ),
      "utf8",
    ),
  ),
);

// The variables and defaults qa/server.mjs and its fixtures start from, so specs reach the stack this run set up.
export const stack = {
  container: process.env.ABS_QA_CONTAINER ?? "leafwake-web-qa",
  feedPort: Number(process.env.ABS_QA_FEED_PORT ?? 19885),
  mailPort: Number(process.env.ABS_QA_MAIL_PORT ?? 19886),
};

export const accounts = {
  admin: { username: "qa-admin", password: "qa-admin-pass" },
  user: { username: "qa", password: "qa-pass" },
  other: { username: "qa-other", password: "qa-other-pass" },
  limited: { username: "qa-limited", password: "qa-limited-pass" },
} as const;

export type Account = (typeof accounts)[keyof typeof accounts];

/** Talks to the QA server directly, as another device would, to observe server-side state. */
export async function serverApi(account: Account) {
  const origin = stateSchema.parse(
    JSON.parse(
      readFileSync(
        new URL(
          `../qa/.runtime/state-${process.env.ABS_QA_CONTAINER ?? "leafwake-web-qa"}.json`,
          import.meta.url,
        ),
        "utf8",
      ),
    ),
  ).origin;
  const login = await fetch(`${origin}/login`, {
    method: "POST",
    headers: { "Content-Type": "application/json", "x-return-tokens": "true" },
    body: JSON.stringify(account),
  });
  const token: string = (await login.json()).user.accessToken;
  async function call(path: string, init: { method?: string; body?: unknown } = {}) {
    const progressPath = path.match(/^\/api\/me\/progress\/([^/]+)(?:\/([^/]+))?$/);
    if (
      init.method === "PATCH" &&
      progressPath &&
      init.body &&
      typeof init.body === "object" &&
      !("progressGeneration" in init.body)
    ) {
      // Fixture setup is a fresh manual intent; capture the same reset generation as current clients.
      const item = await call(`/api/items/${progressPath[1]}`);
      const generation = progressPath[2]
        ? (item.body?.progressGenerations?.[progressPath[2]] ?? 0)
        : (item.body?.progressGeneration ?? 0);
      init = { ...init, body: { ...init.body, progressGeneration: generation } };
    }
    const response = await fetch(origin + path, {
      method: init.method ?? "GET",
      headers: {
        Authorization: `Bearer ${token}`,
        ...(init.body ? { "Content-Type": "application/json" } : {}),
      },
      body: init.body ? JSON.stringify(init.body) : undefined,
    });
    const text = await response.text();
    let body = null;
    try {
      body = text ? JSON.parse(text) : null;
    } catch {}
    return { status: response.status, body };
  }
  return { token, call };
}

/** The path the client is mounted under, such as /web behind a proxy; empty when it serves from the root. */
export const clientPath = new URL(
  process.env.ABS_WEB_URL ?? `http://127.0.0.1:${process.env.ABS_QA_PORT ?? 19880}`,
).pathname.replace(/\/+$/, "");

export async function signIn(page: Page, account: Account = accounts.user, serverUrl = qa.origin) {
  await page.goto(`${clientPath}/connect?server=${encodeURIComponent(serverUrl)}`);
  await page.getByLabel("Username").fill(account.username);
  await page.getByLabel("Password").fill(account.password);
  await page.getByRole("button", { name: "Sign in", exact: true }).click();
  await expect(page.getByRole("navigation", { name: "Library" })).toBeVisible();
}

export async function itemIdByTitle(title: string) {
  const api = await serverApi(accounts.admin);
  const { body } = await api.call(
    `/api/libraries/${qa.libraries.books}/search?q=${encodeURIComponent(title)}`,
  );
  const match = body.book.find(
    (entry: { libraryItem: { id: string; media: { metadata: { title: string } } } }) =>
      entry.libraryItem.media.metadata.title === title,
  );
  if (!match) throw new Error(`No fixture item titled ${title}`);
  return match.libraryItem.id as string;
}

export async function clearProgress(api: Awaited<ReturnType<typeof serverApi>>, itemId: string) {
  const progress = await api.call(`/api/me/progress/${itemId}`);
  if (progress.body?.id) await api.call(`/api/me/progress/${progress.body.id}`, { method: "DELETE" });
}

/** Chooses from one of the app's selects as a person does: opens the labelled field's list and picks by name. */
export async function choose(scope: Page | Locator, label: string, option: string) {
  const page = "keyboard" in scope ? scope : scope.page();
  await scope.getByRole("combobox", { name: label }).click();
  const list = page.getByRole("listbox");
  await list.getByRole("option", { name: option, exact: true }).click();
  await expect(list).toBeHidden();
}
