"use client";

import { createContext, use } from "react";
import { useI18n } from "@/i18n/i18n";
import { rtlLanguages } from "@/i18n/languages";

/**
 * Where popups mount. A modal dialog sits in the browser's top layer and makes the rest of the page inert, so a list
 * or menu opened inside one has to mount inside it rather than at the end of the body.
 */
export const PopupLayer = createContext<HTMLElement | null>(null);

export function usePopupLayer() {
  return use(PopupLayer) ?? undefined;
}

export function useDirection() {
  return rtlLanguages.has(useI18n().code) ? "rtl" : "ltr";
}

export const popupPanel =
  "z-50 min-w-40 overflow-hidden rounded-xl border border-line bg-surface-2 p-1 text-fg shadow-[0_12px_32px_rgb(0_0_0/0.45)] focus:outline-none";

export const popupItem =
  "relative flex min-h-10 cursor-default items-center gap-2.5 rounded-lg ps-9 pe-3 text-sm outline-none select-none data-[disabled]:opacity-40 data-[highlighted]:bg-surface-3 data-[state=checked]:font-semibold";
