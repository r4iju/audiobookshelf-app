import { createHash } from "node:crypto";
import { readdirSync, readFileSync, writeFileSync } from "node:fs";
import {
  carried,
  catalog,
  codes,
  placeholders,
  readTable,
  usable,
  webRoot,
} from "./web-translation-catalog.mjs";

const sha256 = (path) => createHash("sha256").update(readFileSync(path)).digest("hex");
const snapshot = readTable("drafts", "english");
const errors = [];
const copiedProvenance = readTable("source-fallbacks", "provenance");
for (const [path, hash] of Object.entries(copiedProvenance.sourceSha256)) {
  if (sha256(`${webRoot}../${path}`) !== hash) errors.push(`Copied source hash is stale: ${path}`);
}
const sameKeys = (left, right) =>
  JSON.stringify(Object.keys(left).sort()) === JSON.stringify(Object.keys(right).sort());
if (!sameKeys(snapshot, catalog) || Object.keys(catalog).some((key) => snapshot[key] !== catalog[key])) {
  errors.push("English snapshot is stale; review affected drafts before updating it.");
}
const expectedFiles = new Set([
  ...codes.map((code) => `${code}.json`),
  "english.json",
  "provenance.json",
  "README.md",
]);
for (const name of readdirSync(`${webRoot}src/i18n/drafts`)) {
  if (!expectedFiles.has(name)) errors.push(`Stale draft file: ${name}`);
}
for (const name of readdirSync(`${webRoot}src/i18n/source-fallbacks`)) {
  if (!codes.some((code) => name === `${code}.json`) && name !== "provenance.json")
    errors.push(`Stale source fallback file: ${name}`);
}
const coverage = {};
for (const code of codes) {
  const originals = carried(code);
  const source = readTable("source-fallbacks", code);
  const drafts = readTable("drafts", code);
  if (sha256(`${webRoot}src/i18n/source-fallbacks/${code}.json`) !== copiedProvenance.outputSha256[code])
    errors.push(`${code}: copied output hash is stale`);
  if (!sameKeys(source, copiedProvenance.entries[code]))
    errors.push(`${code}: copied provenance keys differ`);
  for (const [key, text] of Object.entries(source)) {
    if (!(key in catalog) || usable(originals[key], catalog[key]))
      errors.push(`${code}.${key}: stale/unneeded copied entry`);
    else if (
      !usable(text, catalog[key]) ||
      (text.match(/\n/g) ?? []).length !== (catalog[key].match(/\n/g) ?? []).length
    )
      errors.push(`${code}.${key}: invalid copied placeholders/newlines`);
  }
  const expected = Object.fromEntries(
    Object.entries(catalog).filter(
      ([key, text]) => !usable(originals[key], text) && !usable(source[key], text),
    ),
  );
  if (!sameKeys(expected, drafts)) {
    errors.push(
      `${code}: missing ${
        Object.keys(expected)
          .filter((key) => !(key in drafts))
          .join(", ") || "none"
      }; stale/unneeded ${
        Object.keys(drafts)
          .filter((key) => !(key in expected))
          .join(", ") || "none"
      }`,
    );
  }
  for (const [key, text] of Object.entries(drafts)) {
    if (!(key in catalog)) continue;
    if (!usable(text, catalog[key]) || placeholders(text) !== placeholders(catalog[key]))
      errors.push(`${code}.${key}: invalid text or placeholder multiset`);
    if (
      typeof text === "string" &&
      (text.match(/\n/g) ?? []).length !== (catalog[key].match(/\n/g) ?? []).length
    )
      errors.push(`${code}.${key}: newline count differs`);
  }
  coverage[code] = {
    entries: Object.keys(catalog).length,
    carried: Object.entries(catalog).filter(([key, text]) => usable(originals[key], text)).length,
    copiedGapSources: Object.keys(source).length,
    machineDrafts: Object.keys(drafts).length,
    englishIdenticalDrafts: Object.entries(drafts).filter(([key, text]) => text === catalog[key]).length,
    missing: Object.entries(catalog)
      .filter(
        ([key, text]) =>
          !usable(originals[key], text) && !usable(source[key], text) && !usable(drafts[key], text),
      )
      .map(([key]) => key),
  };
}
if (errors.length) {
  console.error(errors.join("\n"));
  process.exit(1);
}
writeFileSync(
  `${webRoot}src/i18n/drafts/provenance.json`,
  `${JSON.stringify(
    {
      origin: "Machine-drafted in this implementation session; not native-speaker approved.",
      policy:
        "Only actual missing web entries. Usable legacy/server/native and reviewed source-gap values take precedence. English-identical entries are counted separately, not as distinct translated wording.",
      englishSha256: sha256(`${webRoot}src/i18n/drafts/english.json`),
      draftSha256: Object.fromEntries(
        codes.map((code) => [code, sha256(`${webRoot}src/i18n/drafts/${code}.json`)]),
      ),
      coverage,
    },
    null,
    2,
  )}\n`,
);
console.log(
  `Validated ${codes.length} languages × ${Object.keys(catalog).length} in-use entries; no missing/stale keys, placeholder or newline failures.`,
);
