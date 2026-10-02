import type { LanguageCode } from "./languages";
import enUs from "./strings/en-us.json";
import { webStrings } from "./web-strings";

type Strings = Record<string, string>;
type Loaded = Promise<{ default: Strings }>;

const english: Strings = { ...enUs, ...webStrings };
const placeholders = (text: string) =>
  [...text.matchAll(/\{\d+\}/g)]
    .map(([token]) => token)
    .sort()
    .join(",");

/** Usable carried text wins; broken placeholders must not hide an actual gap's fallback. */
async function withCarried(...tables: Loaded[]) {
  const loaded = await Promise.all(tables);
  const strings: Strings = {};
  for (const table of loaded) {
    for (const [key, text] of Object.entries(table.default)) {
      const source = english[key];
      if (text.trim() && (!source || placeholders(text) === placeholders(source))) strings[key] = text;
    }
  }
  return { default: strings };
}

export const loaders: Record<LanguageCode, () => Loaded> = {
  ar: () =>
    withCarried(
      import("./drafts/ar.json"),
      import("./source-fallbacks/ar.json"),
      import("./strings/ar.json"),
      import("./server-strings/ar.json"),
      import("./native-strings/ar.json"),
    ),
  be: () =>
    withCarried(
      import("./drafts/be.json"),
      import("./source-fallbacks/be.json"),
      import("./strings/be.json"),
      import("./server-strings/be.json"),
      import("./native-strings/be.json"),
    ),
  bg: () =>
    withCarried(
      import("./drafts/bg.json"),
      import("./source-fallbacks/bg.json"),
      import("./strings/bg.json"),
      import("./server-strings/bg.json"),
      import("./native-strings/bg.json"),
    ),
  bn: () =>
    withCarried(
      import("./drafts/bn.json"),
      import("./source-fallbacks/bn.json"),
      import("./strings/bn.json"),
      import("./server-strings/bn.json"),
      import("./native-strings/bn.json"),
    ),
  ca: () =>
    withCarried(
      import("./drafts/ca.json"),
      import("./source-fallbacks/ca.json"),
      import("./strings/ca.json"),
      import("./server-strings/ca.json"),
      import("./native-strings/ca.json"),
    ),
  cs: () =>
    withCarried(
      import("./drafts/cs.json"),
      import("./source-fallbacks/cs.json"),
      import("./strings/cs.json"),
      import("./server-strings/cs.json"),
      import("./native-strings/cs.json"),
    ),
  da: () =>
    withCarried(
      import("./drafts/da.json"),
      import("./source-fallbacks/da.json"),
      import("./strings/da.json"),
      import("./server-strings/da.json"),
      import("./native-strings/da.json"),
    ),
  de: () =>
    withCarried(
      import("./drafts/de.json"),
      import("./source-fallbacks/de.json"),
      import("./strings/de.json"),
      import("./server-strings/de.json"),
      import("./native-strings/de.json"),
    ),
  "en-us": () => import("./strings/en-us.json"),
  es: () =>
    withCarried(
      import("./drafts/es.json"),
      import("./source-fallbacks/es.json"),
      import("./strings/es.json"),
      import("./server-strings/es.json"),
      import("./native-strings/es.json"),
    ),
  fi: () =>
    withCarried(
      import("./drafts/fi.json"),
      import("./source-fallbacks/fi.json"),
      import("./strings/fi.json"),
      import("./server-strings/fi.json"),
      import("./native-strings/fi.json"),
    ),
  fr: () =>
    withCarried(
      import("./drafts/fr.json"),
      import("./source-fallbacks/fr.json"),
      import("./strings/fr.json"),
      import("./server-strings/fr.json"),
      import("./native-strings/fr.json"),
    ),
  he: () =>
    withCarried(
      import("./drafts/he.json"),
      import("./source-fallbacks/he.json"),
      import("./strings/he.json"),
      import("./server-strings/he.json"),
      import("./native-strings/he.json"),
    ),
  hr: () =>
    withCarried(
      import("./drafts/hr.json"),
      import("./source-fallbacks/hr.json"),
      import("./strings/hr.json"),
      import("./server-strings/hr.json"),
      import("./native-strings/hr.json"),
    ),
  hu: () =>
    withCarried(
      import("./drafts/hu.json"),
      import("./source-fallbacks/hu.json"),
      import("./strings/hu.json"),
      import("./server-strings/hu.json"),
      import("./native-strings/hu.json"),
    ),
  it: () =>
    withCarried(
      import("./drafts/it.json"),
      import("./source-fallbacks/it.json"),
      import("./strings/it.json"),
      import("./server-strings/it.json"),
      import("./native-strings/it.json"),
    ),
  ko: () =>
    withCarried(
      import("./drafts/ko.json"),
      import("./source-fallbacks/ko.json"),
      import("./strings/ko.json"),
      import("./native-strings/ko.json"),
    ),
  lt: () =>
    withCarried(
      import("./drafts/lt.json"),
      import("./source-fallbacks/lt.json"),
      import("./strings/lt.json"),
      import("./server-strings/lt.json"),
      import("./native-strings/lt.json"),
    ),
  nl: () =>
    withCarried(
      import("./drafts/nl.json"),
      import("./source-fallbacks/nl.json"),
      import("./strings/nl.json"),
      import("./server-strings/nl.json"),
      import("./native-strings/nl.json"),
    ),
  no: () =>
    withCarried(
      import("./drafts/no.json"),
      import("./source-fallbacks/no.json"),
      import("./strings/no.json"),
      import("./server-strings/no.json"),
      import("./native-strings/no.json"),
    ),
  pl: () =>
    withCarried(
      import("./drafts/pl.json"),
      import("./source-fallbacks/pl.json"),
      import("./strings/pl.json"),
      import("./server-strings/pl.json"),
      import("./native-strings/pl.json"),
    ),
  "pt-br": () =>
    withCarried(
      import("./drafts/pt-br.json"),
      import("./source-fallbacks/pt-br.json"),
      import("./strings/pt-br.json"),
      import("./server-strings/pt-br.json"),
      import("./native-strings/pt-br.json"),
    ),
  ru: () =>
    withCarried(
      import("./drafts/ru.json"),
      import("./source-fallbacks/ru.json"),
      import("./strings/ru.json"),
      import("./server-strings/ru.json"),
      import("./native-strings/ru.json"),
    ),
  sk: () =>
    withCarried(
      import("./drafts/sk.json"),
      import("./source-fallbacks/sk.json"),
      import("./strings/sk.json"),
      import("./server-strings/sk.json"),
      import("./native-strings/sk.json"),
    ),
  sl: () =>
    withCarried(
      import("./drafts/sl.json"),
      import("./source-fallbacks/sl.json"),
      import("./strings/sl.json"),
      import("./server-strings/sl.json"),
      import("./native-strings/sl.json"),
    ),
  sv: () =>
    withCarried(
      import("./drafts/sv.json"),
      import("./source-fallbacks/sv.json"),
      import("./strings/sv.json"),
      import("./server-strings/sv.json"),
      import("./native-strings/sv.json"),
    ),
  tr: () =>
    withCarried(
      import("./drafts/tr.json"),
      import("./source-fallbacks/tr.json"),
      import("./strings/tr.json"),
      import("./server-strings/tr.json"),
      import("./native-strings/tr.json"),
    ),
  uk: () =>
    withCarried(
      import("./drafts/uk.json"),
      import("./source-fallbacks/uk.json"),
      import("./strings/uk.json"),
      import("./server-strings/uk.json"),
      import("./native-strings/uk.json"),
    ),
  "vi-vn": () =>
    withCarried(
      import("./drafts/vi-vn.json"),
      import("./source-fallbacks/vi-vn.json"),
      import("./strings/vi-vn.json"),
      import("./server-strings/vi-vn.json"),
      import("./native-strings/vi-vn.json"),
    ),
  "zh-cn": () =>
    withCarried(
      import("./drafts/zh-cn.json"),
      import("./source-fallbacks/zh-cn.json"),
      import("./strings/zh-cn.json"),
      import("./server-strings/zh-cn.json"),
      import("./native-strings/zh-cn.json"),
    ),
};
