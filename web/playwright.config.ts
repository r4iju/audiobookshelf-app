import { defineConfig, devices } from "@playwright/test";

// Existing browser journeys consume the same one-image synthetic installation as native QA.
const clientUrl = process.env.ABS_WEB_URL ?? `http://127.0.0.1:${process.env.ABS_QA_PORT ?? 19880}`;
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
});
