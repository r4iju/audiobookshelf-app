import { mkdir, readdir, readFile, writeFile } from "node:fs/promises";
import { join } from "node:path";
import { fileURLToPath } from "node:url";

const root = fileURLToPath(new URL("../", import.meta.url));
const inventory = [];
const notices = [];
async function licenses(directory, prefix = "") {
  for (const entry of await readdir(directory, { withFileTypes: true })) {
    if (entry.isSymbolicLink() || entry.name === "node_modules") continue;
    const path = join(directory, entry.name),
      relative = prefix + entry.name;
    if (entry.isDirectory()) await licenses(path, relative + "/");
    else if (entry.isFile() && /^(licen[cs]e|copying|notice|copyright)([._-].*)?$/i.test(entry.name)) {
      const text = await readFile(path, "utf8");
      notices.push(`${relative}\n${text}`);
    }
  }
}
async function packages(directory) {
  for (const entry of await readdir(directory, { withFileTypes: true })) {
    if (!entry.isDirectory() || entry.name.startsWith(".")) continue;
    const path = join(directory, entry.name);
    if (entry.name.startsWith("@")) {
      await packages(path);
      continue;
    }
    let metadata;
    try {
      metadata = JSON.parse(await readFile(join(path, "package.json"), "utf8"));
    } catch (error) {
      if (error.code === "ENOENT") continue;
      throw error;
    }
    inventory.push({ name: metadata.name, version: metadata.version, license: metadata.license ?? null });
    await licenses(path, `${metadata.name}@${metadata.version}/`);
    try {
      await packages(join(path, "node_modules"));
    } catch (error) {
      if (error.code !== "ENOENT") throw error;
    }
  }
}
await packages(join(root, "node_modules"));
notices.push(await readFile(join(root, "vendor/libarchive/NOTICES.txt"), "utf8"));
inventory.sort((a, b) => a.name.localeCompare(b.name) || a.version.localeCompare(b.version));
notices.sort();
await mkdir(join(root, "public"), { recursive: true });
await writeFile(join(root, "public", "web-dependencies.json"), JSON.stringify(inventory, null, 2) + "\n");
await writeFile(
  join(root, "public", "THIRD-PARTY-NOTICES.txt"),
  "Leafwake web/runtime dependency notices\n\n" +
    inventory.map((p) => `${p.name}@${p.version}: ${JSON.stringify(p.license)}`).join("\n") +
    "\n\n" +
    notices.join("\n\n"),
);
