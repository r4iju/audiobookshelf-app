// Serve the audited decoder, rather than the npm binary linked with pre-3.0 OpenSSL.
import { createHash } from "node:crypto";
import { copyFileSync, mkdirSync, readFileSync } from "node:fs";
import { join } from "node:path";
import { fileURLToPath } from "node:url";

const dist = fileURLToPath(new URL("../vendor/libarchive/", import.meta.url));
const provenance = JSON.parse(readFileSync(join(dist, "provenance.json"), "utf8"));
const target = fileURLToPath(new URL("../public/libarchive/", import.meta.url));
mkdirSync(target, { recursive: true });
for (const name of ["worker-bundle.js", "libarchive.wasm"]) {
  const checksum = createHash("sha256")
    .update(readFileSync(join(dist, name)))
    .digest("hex");
  if (provenance.openssl !== false || checksum !== provenance.artifacts[name])
    throw new Error(`Comic decoder provenance mismatch: ${name}`);
  copyFileSync(join(dist, name), join(target, name));
}
