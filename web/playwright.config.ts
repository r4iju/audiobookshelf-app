import { defineConfig, devices } from "@playwright/test";

// Journeys drive the production UI against an isolated, unmodified Audiobookshelf 2.30.0 container (qa/server.mjs).
// ABS_WEB_URL selects an already running client (for example the nginx same-origin deployment); otherwise the dev
// server is started on 19881, a port shared with neither the Apple fixture nor the Android worker.
const clientUrl = process.env.ABS_WEB_URL ?? "http://127.0.0.1:19881";

export default defineConfig({
  testDir: "e2e",
  fullyParallel: false,
  workers: 1,
  timeout: 60_000,
  expect: { timeout: 10_000 },
  reporter: [["list"]],
  globalSetup: "./e2e/global-setup.ts",
  use: {
    baseURL: clientUrl,
    trace: "retain-on-failure",
    screenshot: "only-on-failure",
    // Real media autoplay after a user gesture is what we verify; this flag only lifts the gesture requirement
    // for programmatic resume after reload, which journeys check explicitly.
    launchOptions: { args: ["--autoplay-policy=user-gesture-required"] },
  },
  projects: [{ name: "chromium", use: { ...devices["Desktop Chrome"] } }],
  webServer: [
    // The QA server downloads podcast feeds and episodes from here (qa/feed.mjs).
    { command: "node qa/feed.mjs", url: "http://127.0.0.1:19885/feed.xml", reuseExistingServer: true },
    // The mail server the QA server sends ebooks to devices through (qa/mail.mjs).
    { command: "node qa/mail.mjs", port: 19886, reuseExistingServer: true },
    // The identity provider for OpenID sign-in (qa/oidc.mjs), used by the deployment journeys.
    {
      command: "node qa/oidc.mjs",
      url: "http://127.0.0.1:19884/.well-known/openid-configuration",
      reuseExistingServer: true,
    },
    ...(process.env.ABS_WEB_URL
      ? []
      : [
          {
            command: process.env.ABS_WEB_PROD ? "npm run build && npm run start" : "npm run dev",
            url: clientUrl,
            reuseExistingServer: true,
            timeout: 240_000,
          },
        ]),
  ],
});
