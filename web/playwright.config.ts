import { defineConfig, devices } from "@playwright/test";

// Journeys drive the production UI against an isolated, unmodified Audiobookshelf 2.30.0 container (qa/server.mjs).
// ABS_WEB_URL selects an already running client (for example the nginx same-origin deployment); otherwise the dev
// server is started on 19881, a port shared with neither the Apple fixture nor the Android worker.
const clientUrl = process.env.ABS_WEB_URL ?? "http://127.0.0.1:19881";
// ABS_WEB_ENGINES=chromium,firefox,webkit adds engines; each must first be installed (npx playwright install <name>).
const engines = (process.env.ABS_WEB_ENGINES ?? "chromium").split(",");

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
  },
  projects: [
    {
      name: "chromium",
      use: {
        ...devices["Desktop Chrome"],
        // Real media autoplay after a user gesture is what we verify; this flag only lifts the gesture requirement
        // for programmatic resume after reload, which journeys check explicitly.
        launchOptions: { args: ["--autoplay-policy=user-gesture-required"] },
      },
    },
    { name: "firefox", use: { ...devices["Desktop Firefox"] } },
    { name: "webkit", use: { ...devices["Desktop Safari"] } },
  ].filter((project) => engines.includes(project.name)),
  webServer: [
    // The feed, mail and OpenID fixtures run beside the QA server, started by qa/server.mjs in global setup.
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
