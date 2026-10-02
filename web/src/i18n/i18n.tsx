"use client";

import { createContext, type ReactNode, use, useEffect, useMemo, useState } from "react";
import { type LanguageCode, localeTag, rtlLanguages } from "./languages";
import { loaders } from "./loaders";
import enUs from "./strings/en-us.json";
import { webStrings } from "./web-strings";

export type StringKey = keyof typeof enUs | keyof typeof webStrings;
const english: Record<string, string> = { ...enUs, ...webStrings };

export function isStringKey(key: string | null | undefined): key is StringKey {
  return typeof key === "string" && key in english;
}

export type Translate = (key: StringKey, ...subs: Array<string | number>) => string;

interface I18n {
  code: LanguageCode;
  locale: string;
  t: Translate;
}

const I18nContext = createContext<I18n | null>(null);

function supplant(text: string, subs: Array<string | number>, numbers: Intl.NumberFormat) {
  return text.replace(/{(\d+)}/g, (match, index: string) => {
    const value = subs[Number(index)];
    if (value === undefined) return match;
    return typeof value === "number" ? numbers.format(value) : value;
  });
}

/**
 * A count passed first picks the key's `_one` variant where the language uses its singular. English strings stand in
 * for missing translations, so they are pluralised by English rules.
 */
export function translate(strings: Record<string, string> | null, locale: string): Translate {
  const numbers = new Intl.NumberFormat(locale);
  const plurals = { own: new Intl.PluralRules(locale), english: new Intl.PluralRules("en") };
  return (key, ...subs) => {
    const translated = strings?.[key] ? strings : null;
    const source = translated ?? english;
    const count = subs[0];
    const singular =
      typeof count === "number" && plurals[translated ? "own" : "english"].select(count) === "one"
        ? source[`${key}_one`]
        : undefined;
    return supplant(singular || source[key] || key, subs, numbers);
  };
}

export function I18nProvider({ code, children }: { code: LanguageCode; children: ReactNode }) {
  const [loaded, setLoaded] = useState<{ code: LanguageCode; strings: Record<string, string> } | null>(null);

  // External system: the translation bundle for the chosen language is code-split and fetched on demand.
  useEffect(() => {
    if (code === "en-us") return;
    let current = true;
    loaders[code]().then((module) => {
      if (current) setLoaded({ code, strings: module.default });
    });
    return () => {
      current = false;
    };
  }, [code]);

  // External system: the document element is outside React's tree.
  useEffect(() => {
    document.documentElement.lang = localeTag(code);
    document.documentElement.dir = rtlLanguages.has(code) ? "rtl" : "ltr";
  }, [code]);

  const value = useMemo<I18n>(() => {
    const strings = loaded?.code === code ? loaded.strings : null;
    return { code, locale: localeTag(code), t: translate(strings, localeTag(code)) };
  }, [code, loaded]);

  return <I18nContext value={value}>{children}</I18nContext>;
}

export function useI18n() {
  const value = use(I18nContext);
  if (!value) throw new Error("useI18n outside I18nProvider");
  return value;
}
