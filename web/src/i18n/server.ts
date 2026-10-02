import { cookies } from "next/headers";
import { cache } from "react";
import { LANGUAGE_COOKIE } from "./language-cookie";
import { isLanguageCode } from "./languages";
import { loaders } from "./loaders";

/** Shared by layout and metadata within a request; never caches a visitor's choice across requests. */
export const initialLanguage = cache(async () => {
  const saved = (await cookies()).get(LANGUAGE_COOKIE)?.value;
  const code = isLanguageCode(saved) ? saved : "en-us";
  const { default: strings } = await loaders[code]();
  return { code, strings };
});
