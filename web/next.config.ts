import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import type { NextConfig } from "next";

// The client is mounted under a reverse-proxy path chosen at build time (for example /web next to the
// Audiobookshelf server). Next.js only supports a build-time basePath, so the Docker image takes it as a build arg.
const basePath = process.env.ABS_WEB_BASE_PATH?.replace(/\/+$/, "") || "";

const { version } = JSON.parse(readFileSync(new URL("./package.json", import.meta.url), "utf8"));

const config: NextConfig = {
  basePath,
  reactStrictMode: true,
  poweredByHeader: false,
  env: { NEXT_PUBLIC_BASE_PATH: basePath, NEXT_PUBLIC_CLIENT_VERSION: version },
  // The repository root has the legacy app's lockfile; this package is its own root.
  turbopack: { root: fileURLToPath(new URL(".", import.meta.url)) },
  outputFileTracingRoot: fileURLToPath(new URL(".", import.meta.url)),
  allowedDevOrigins: ["127.0.0.1", "localhost"],
  // The dev tools button is the first tab stop otherwise, which hides keyboard-order problems during development.
  devIndicators: false,
};

export default config;
