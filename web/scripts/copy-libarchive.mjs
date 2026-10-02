// libarchive.js loads its worker and the wasm beside it at run time, so both are served as they ship.
import { copyFileSync, mkdirSync } from "node:fs";
import { createRequire } from "node:module";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const dist = dirname(createRequire(import.meta.url).resolve("libarchive.js"));
const target = fileURLToPath(new URL("../public/libarchive/", import.meta.url));
mkdirSync(target, { recursive: true });
for (const name of ["worker-bundle.js", "libarchive.wasm"])
  copyFileSync(join(dist, name), join(target, name));
