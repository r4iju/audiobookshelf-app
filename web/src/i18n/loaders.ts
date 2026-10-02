import type { LanguageCode } from "./languages";

type Strings = Record<string, string>;
type Loaded = Promise<{ default: Strings }>;

/** The legacy client's translations, with the server interface's for web strings that mean the same as its keys. */
async function withServer(legacy: Loaded, server: Loaded) {
  const [own, carried] = await Promise.all([legacy, server]);
  return { default: { ...own.default, ...carried.default } };
}

export const loaders: Record<LanguageCode, () => Loaded> = {
  ar: () => withServer(import("./strings/ar.json"), import("./server-strings/ar.json")),
  be: () => withServer(import("./strings/be.json"), import("./server-strings/be.json")),
  bg: () => withServer(import("./strings/bg.json"), import("./server-strings/bg.json")),
  bn: () => withServer(import("./strings/bn.json"), import("./server-strings/bn.json")),
  ca: () => withServer(import("./strings/ca.json"), import("./server-strings/ca.json")),
  cs: () => withServer(import("./strings/cs.json"), import("./server-strings/cs.json")),
  da: () => withServer(import("./strings/da.json"), import("./server-strings/da.json")),
  de: () => withServer(import("./strings/de.json"), import("./server-strings/de.json")),
  "en-us": () => import("./strings/en-us.json"),
  es: () => withServer(import("./strings/es.json"), import("./server-strings/es.json")),
  fi: () => withServer(import("./strings/fi.json"), import("./server-strings/fi.json")),
  fr: () => withServer(import("./strings/fr.json"), import("./server-strings/fr.json")),
  he: () => withServer(import("./strings/he.json"), import("./server-strings/he.json")),
  hr: () => withServer(import("./strings/hr.json"), import("./server-strings/hr.json")),
  hu: () => withServer(import("./strings/hu.json"), import("./server-strings/hu.json")),
  it: () => withServer(import("./strings/it.json"), import("./server-strings/it.json")),
  ko: () => import("./strings/ko.json"),
  lt: () => withServer(import("./strings/lt.json"), import("./server-strings/lt.json")),
  nl: () => withServer(import("./strings/nl.json"), import("./server-strings/nl.json")),
  no: () => withServer(import("./strings/no.json"), import("./server-strings/no.json")),
  pl: () => withServer(import("./strings/pl.json"), import("./server-strings/pl.json")),
  "pt-br": () => withServer(import("./strings/pt-br.json"), import("./server-strings/pt-br.json")),
  ru: () => withServer(import("./strings/ru.json"), import("./server-strings/ru.json")),
  sk: () => withServer(import("./strings/sk.json"), import("./server-strings/sk.json")),
  sl: () => withServer(import("./strings/sl.json"), import("./server-strings/sl.json")),
  sv: () => withServer(import("./strings/sv.json"), import("./server-strings/sv.json")),
  tr: () => withServer(import("./strings/tr.json"), import("./server-strings/tr.json")),
  uk: () => withServer(import("./strings/uk.json"), import("./server-strings/uk.json")),
  "vi-vn": () => withServer(import("./strings/vi-vn.json"), import("./server-strings/vi-vn.json")),
  "zh-cn": () => withServer(import("./strings/zh-cn.json"), import("./server-strings/zh-cn.json")),
};
