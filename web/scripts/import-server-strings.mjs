// Carries the server web interface's translations over for web strings that mean the same as one of its keys
// (src/i18n/server-equivalents.json). The values are copied unchanged into src/i18n/server-strings/<code>.json.
//
// The source is the server's own translation tables: a directory of <code>.json files (client/strings in the server's
// source), or the built interface's script bundles, which ship the same tables:
//   docker create --name abs-strings <server image> && docker cp abs-strings:/app/client/dist/_nuxt <dir>
//   docker rm abs-strings && node scripts/import-server-strings.mjs <dir>
import { mkdirSync, readdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { languages } from "../src/i18n/languages.ts";
import { webStrings } from "../src/i18n/web-strings.ts";

const source = process.argv[2];
if (!source)
  throw new Error("usage: node scripts/import-server-strings.mjs <server strings or bundle directory>");
const i18n = new URL("../src/i18n/", import.meta.url);
const target = new URL("server-strings/", i18n);
const equivalents = JSON.parse(readFileSync(new URL("server-equivalents.json", i18n), "utf8"));

function serverTables(dir) {
  const files = readdirSync(dir);
  if (files.includes("en-us.json"))
    return Object.fromEntries(
      files
        .filter((name) => name.endsWith(".json"))
        .map((name) => [name.slice(0, -5), JSON.parse(readFileSync(join(dir, name), "utf8"))]),
    );
  // Built bundles: each table is a JSON.parse('…') module, and a lazy-loading map names its file ("./de.json":[id,…]).
  const scripts = files
    .filter((name) => name.endsWith(".js"))
    .map((name) => readFileSync(join(dir, name), "utf8"));
  const names = {};
  for (const script of scripts)
    for (const [, code, id] of script.matchAll(/"\.\/([a-z-]+)\.json":\[(\d+),/g)) names[id] = code;
  const tables = {};
  for (const script of scripts)
    for (const [, id, literal] of script.matchAll(
      /(\d*):?function\(\w\)\{\w\.exports=JSON\.parse\('((?:[^'\\]|\\.)*)'\)\}/g,
    )) {
      const table = JSON.parse(new Function(`return '${literal}'`)());
      if (!table.ButtonAdd) continue;
      tables[names[id] ?? (table.ButtonAdd === "Add" ? "en-us" : `unnamed-${id}`)] = table;
    }
  return tables;
}

const placeholders = (text) =>
  [...text.matchAll(/\{\d+\}/g)]
    .map(([p]) => p)
    .sort()
    .join();
const tables = serverTables(source);
const english = tables["en-us"];
if (!english) throw new Error(`no English table in ${source}`);

for (const [web, server] of Object.entries(equivalents)) {
  if (!(web in webStrings)) throw new Error(`${web} is not a web string`);
  if (!(server in english)) throw new Error(`${server} is not in the server's English table`);
  if (placeholders(webStrings[web]) !== placeholders(english[server]))
    throw new Error(`${web} and ${server} take different placeholders`);
}

rmSync(target, { recursive: true, force: true });
mkdirSync(target);
const counts = {};
for (const code of Object.keys(languages)) {
  const table = tables[code];
  if (code === "en-us" || !table) continue;
  const strings = {};
  for (const [web, server] of Object.entries(equivalents)) {
    const text = table[server];
    // Missing, copied-English or placeholder-changing entries are left to the English fallback.
    if (text?.trim() && text !== english[server] && placeholders(text) === placeholders(english[server]))
      strings[web] = text;
  }
  writeFileSync(new URL(`${code}.json`, target), `${JSON.stringify(strings, null, 2)}\n`, { flag: "wx" });
  counts[code] = Object.keys(strings).length;
}
console.log(`${Object.keys(equivalents).length} equivalents`, counts);
