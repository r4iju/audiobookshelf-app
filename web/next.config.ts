import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import type { NextConfig } from "next";

// The whole product can use a build-time reverse-proxy subpath. Browser, API and realtime share it.
const basePath = process.env.ABS_WEB_BASE_PATH?.replace(/\/+$/, "") || "";

const { version } = JSON.parse(readFileSync(new URL("./package.json", import.meta.url), "utf8"));

const config: NextConfig = {
  basePath,
  reactStrictMode: true,
  poweredByHeader: false,
  env: { NEXT_PUBLIC_BASE_PATH: basePath, NEXT_PUBLIC_CLIENT_VERSION: version },
  // The browser/backend package owns its build root.
  turbopack: { root: fileURLToPath(new URL(".", import.meta.url)) },
  outputFileTracingRoot: fileURLToPath(new URL(".", import.meta.url)),
  allowedDevOrigins: ["127.0.0.1", "localhost"],
  // The dev tools button is the first tab stop otherwise, which hides keyboard-order problems during development.
  devIndicators: false,
};

export default config;
