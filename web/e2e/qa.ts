import { readFileSync } from "node:fs";
import { expect, type Page } from "@playwright/test";
import { z } from "zod";

const stateSchema = z.object({
  origin: z.string(),
  serverVersion: z.string(),
  libraries: z.object({ books: z.string(), podcasts: z.string() }),
  users: z.object({ user: z.string(), other: z.string(), limited: z.string() }),
});

export const qa = stateSchema.parse(
  JSON.parse(readFileSync(new URL("../qa/.runtime/state.json", import.meta.url), "utf8")),
);

export const accounts = {
  admin: { username: "qa-admin", password: "qa-admin-pass" },
  user: { username: "qa", password: "qa-pass" },
  other: { username: "qa-other", password: "qa-other-pass" },
  limited: { username: "qa-limited", password: "qa-limited-pass" },
} as const;

export type Account = (typeof accounts)[keyof typeof accounts];

/** Talks to the QA server directly, as another device would, to observe server-side state. */
export async function serverApi(account: Account) {
  const login = await fetch(`${qa.origin}/login`, {
    method: "POST",
    headers: { "Content-Type": "application/json", "x-return-tokens": "true" },
    body: JSON.stringify(account),
  });
  const token: string = (await login.json()).user.accessToken;
  async function call(path: string, init: { method?: string; body?: unknown } = {}) {
    const response = await fetch(qa.origin + path, {
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

export async function signIn(page: Page, account: Account = accounts.user, serverUrl = qa.origin) {
  await page.goto("/connect");
  await page.getByLabel("Server address").fill(serverUrl);
  await page.getByRole("button", { name: "Continue" }).click();
  await page.getByLabel("Username").fill(account.username);
  await page.getByLabel("Password").fill(account.password);
  await page.getByRole("button", { name: "Sign in" }).click();
  await expect(page.getByRole("navigation", { name: "Library" })).toBeVisible();
}
