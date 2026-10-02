import type { LanguageCode } from "./languages";

type Strings = Record<string, string>;
type Loaded = Promise<{ default: Strings }>;

/** Reviewed equivalents carry maintained server and native translations into the web client. */
async function withCarried(...tables: Loaded[]) {
  const loaded = await Promise.all(tables);
  const strings: Strings = {};
  for (const table of loaded) Object.assign(strings, table.default);
  return { default: strings };
}

export const loaders: Record<LanguageCode, () => Loaded> = {
  ar: () =>
    withCarried(
      import("./strings/ar.json"),
      import("./server-strings/ar.json"),
      import("./native-strings/ar.json"),
    ),
  be: () =>
    withCarried(
      import("./strings/be.json"),
      import("./server-strings/be.json"),
      import("./native-strings/be.json"),
    ),
  bg: () =>
    withCarried(
      import("./strings/bg.json"),
      import("./server-strings/bg.json"),
      import("./native-strings/bg.json"),
    ),
  bn: () =>
    withCarried(
      import("./strings/bn.json"),
      import("./server-strings/bn.json"),
      import("./native-strings/bn.json"),
    ),
  ca: () =>
    withCarried(
      import("./strings/ca.json"),
      import("./server-strings/ca.json"),
      import("./native-strings/ca.json"),
    ),
  cs: () =>
    withCarried(
      import("./strings/cs.json"),
      import("./server-strings/cs.json"),
      import("./native-strings/cs.json"),
    ),
  da: () =>
    withCarried(
      import("./strings/da.json"),
      import("./server-strings/da.json"),
      import("./native-strings/da.json"),
    ),
  de: () =>
    withCarried(
      import("./strings/de.json"),
      import("./server-strings/de.json"),
      import("./native-strings/de.json"),
    ),
  "en-us": () => import("./strings/en-us.json"),
  es: () =>
    withCarried(
      import("./strings/es.json"),
      import("./server-strings/es.json"),
      import("./native-strings/es.json"),
    ),
  fi: () =>
    withCarried(
      import("./strings/fi.json"),
      import("./server-strings/fi.json"),
      import("./native-strings/fi.json"),
    ),
  fr: () =>
    withCarried(
      import("./strings/fr.json"),
      import("./server-strings/fr.json"),
      import("./native-strings/fr.json"),
    ),
  he: () =>
    withCarried(
      import("./strings/he.json"),
      import("./server-strings/he.json"),
      import("./native-strings/he.json"),
    ),
  hr: () =>
    withCarried(
      import("./strings/hr.json"),
      import("./server-strings/hr.json"),
      import("./native-strings/hr.json"),
    ),
  hu: () =>
    withCarried(
      import("./strings/hu.json"),
      import("./server-strings/hu.json"),
      import("./native-strings/hu.json"),
    ),
  it: () =>
    withCarried(
      import("./strings/it.json"),
      import("./server-strings/it.json"),
      import("./native-strings/it.json"),
    ),
  ko: () => withCarried(import("./strings/ko.json"), import("./native-strings/ko.json")),
  lt: () =>
    withCarried(
      import("./strings/lt.json"),
      import("./server-strings/lt.json"),
      import("./native-strings/lt.json"),
    ),
  nl: () =>
    withCarried(
      import("./strings/nl.json"),
      import("./server-strings/nl.json"),
      import("./native-strings/nl.json"),
    ),
  no: () =>
    withCarried(
      import("./strings/no.json"),
      import("./server-strings/no.json"),
      import("./native-strings/no.json"),
    ),
  pl: () =>
    withCarried(
      import("./strings/pl.json"),
      import("./server-strings/pl.json"),
      import("./native-strings/pl.json"),
    ),
  "pt-br": () =>
    withCarried(
      import("./strings/pt-br.json"),
      import("./server-strings/pt-br.json"),
      import("./native-strings/pt-br.json"),
    ),
  ru: () =>
    withCarried(
      import("./strings/ru.json"),
      import("./server-strings/ru.json"),
      import("./native-strings/ru.json"),
    ),
  sk: () =>
    withCarried(
      import("./strings/sk.json"),
      import("./server-strings/sk.json"),
      import("./native-strings/sk.json"),
    ),
  sl: () =>
    withCarried(
      import("./strings/sl.json"),
      import("./server-strings/sl.json"),
      import("./native-strings/sl.json"),
    ),
  sv: () =>
    withCarried(
      import("./strings/sv.json"),
      import("./server-strings/sv.json"),
      import("./native-strings/sv.json"),
    ),
  tr: () =>
    withCarried(
      import("./strings/tr.json"),
      import("./server-strings/tr.json"),
      import("./native-strings/tr.json"),
    ),
  uk: () =>
    withCarried(
      import("./strings/uk.json"),
      import("./server-strings/uk.json"),
      import("./native-strings/uk.json"),
    ),
  "vi-vn": () =>
    withCarried(
      import("./strings/vi-vn.json"),
      import("./server-strings/vi-vn.json"),
      import("./native-strings/vi-vn.json"),
    ),
  "zh-cn": () =>
    withCarried(
      import("./strings/zh-cn.json"),
      import("./server-strings/zh-cn.json"),
      import("./native-strings/zh-cn.json"),
    ),
};
