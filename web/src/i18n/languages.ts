// The languages the legacy client offered, with its translations carried over unchanged. Strings introduced by this
// client live in web-strings.ts (English) and fall back to English until translated.
export const languages = {
  ar: "عربي",
  be: "Беларуская",
  bg: "Български",
  bn: "বাংলা",
  ca: "Català",
  cs: "Čeština",
  da: "Dansk",
  de: "Deutsch",
  "en-us": "English",
  es: "Español",
  fi: "Suomi",
  fr: "Français",
  he: "עברית",
  hr: "Hrvatski",
  it: "Italiano",
  lt: "Lietuvių",
  hu: "Magyar",
  ko: "한국어",
  nl: "Nederlands",
  no: "Norsk",
  pl: "Polski",
  "pt-br": "Português (Brasil)",
  ru: "Русский",
  sk: "Slovenčina",
  sl: "Slovenščina",
  sv: "Svenska",
  tr: "Türkçe",
  uk: "Українська",
  "vi-vn": "Tiếng Việt",
  "zh-cn": "简体中文 (Simplified Chinese)",
} as const;

export type LanguageCode = keyof typeof languages;

export function isLanguageCode(value: string | null | undefined): value is LanguageCode {
  return !!value && Object.hasOwn(languages, value);
}

export const rtlLanguages = new Set<LanguageCode>(["ar", "he"]);

/** BCP 47 tag for Intl formatting and the document language. */
export function localeTag(code: LanguageCode) {
  return code === "en-us"
    ? "en-US"
    : code.replace(/-([a-z]+)$/, (_, region: string) => `-${region.toUpperCase()}`);
}
