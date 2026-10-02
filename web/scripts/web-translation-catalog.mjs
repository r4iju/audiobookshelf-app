import { readdirSync, readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { webStrings } from "../src/i18n/web-strings.ts";

export const webRoot = fileURLToPath(new URL("../", import.meta.url));
const source = readdirSync(`${webRoot}src`, { recursive: true })
  .filter((path) => /\.(ts|tsx)$/.test(path) && !path.startsWith("i18n/") && !path.endsWith(".test.ts"))
  .map((path) => readFileSync(`${webRoot}src/${path}`, "utf8"))
  .join("\n");
const inUse = (key) =>
  source.includes(`"${key}"`) || (key.endsWith("_one") && source.includes(`"${key.slice(0, -4)}"`));
const inherited = JSON.parse(readFileSync(`${webRoot}src/i18n/strings/en-us.json`, "utf8"));
export const catalog = Object.fromEntries([
  ...Object.entries(webStrings).filter(([key]) => inUse(key)),
  ...Object.entries(inherited).filter(([key]) => !(key in webStrings) && inUse(key)),
]);
export const codes = readdirSync(`${webRoot}src/i18n/strings`)
  .filter((path) => path.endsWith(".json") && path !== "en-us.json")
  .map((path) => path.slice(0, -5))
  .sort();
export const readTable = (kind, code) => {
  try {
    return JSON.parse(readFileSync(`${webRoot}src/i18n/${kind}/${code}.json`, "utf8"));
  } catch (error) {
    if (error.code === "ENOENT") return {};
    throw error;
  }
};
export const placeholders = (text) =>
  [...text.matchAll(/\{\d+\}/g)]
    .map(([token]) => token)
    .sort()
    .join(",");
export const usable = (text, english) =>
  typeof text === "string" && text.trim().length > 0 && placeholders(text) === placeholders(english);
export const carried = (code) => {
  const result = {};
  for (const kind of ["strings", "server-strings", "native-strings"]) {
    for (const [key, text] of Object.entries(readTable(kind, code))) {
      if (!(key in catalog) || usable(text, catalog[key])) result[key] = text;
    }
  }
  return result;
};
