"use client";

import { MutationCache, QueryCache, QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { type ReactNode, useEffect, useState } from "react";
import { I18nProvider } from "@/i18n/i18n";
import { isLanguageCode, type LanguageCode } from "@/i18n/languages";
import { AbsError } from "@/lib/abs/client";
import { useSession, useSessionStore } from "@/lib/session/store";
import { SETTINGS_STORAGE_KEY, useSettingsStore } from "@/lib/settings/store";

function onError(error: unknown) {
  if (error instanceof AbsError && error.kind === "unauthorized") useSessionStore.getState().requireReauth();
}

function makeQueryClient() {
  return new QueryClient({
    queryCache: new QueryCache({ onError }),
    mutationCache: new MutationCache({ onError }),
    defaultOptions: {
      queries: {
        staleTime: 30_000,
        refetchOnWindowFocus: true,
        retry: (count, error) =>
          error instanceof AbsError && (error.kind === "network" || error.kind === "http") && count < 2,
      },
    },
  });
}

export function AppProviders({
  children,
  initialLanguage,
}: {
  children: ReactNode;
  initialLanguage: { code: LanguageCode; strings: Record<string, string> };
}) {
  const [queryClient] = useState(makeQueryClient);
  const settings = useSettingsStore((state) => state.settings);
  const hydrated = useSettingsStore((state) => state.hydrated);
  const session = useSession();

  // External system: localStorage holds settings and saved servers; other tabs change them too.
  useEffect(() => {
    useSettingsStore.getState().hydrate();
    useSessionStore.getState().restore();
    const onStorage = (event: StorageEvent) => {
      if (event.key === SETTINGS_STORAGE_KEY) useSettingsStore.getState().hydrate();
      if (event.key === "abs-web:v1:connections") useSessionStore.getState().restore();
    };
    window.addEventListener("storage", onStorage);
    return () => window.removeEventListener("storage", onStorage);
  }, []);

  // External system: theme and motion preferences are applied to the document element.
  useEffect(() => {
    const root = document.documentElement;
    const media = matchMedia("(prefers-color-scheme: light)");
    const apply = () => {
      root.dataset.theme = settings.theme === "system" ? (media.matches ? "light" : "dark") : settings.theme;
    };
    apply();
    root.dataset.reduceMotion = String(settings.reduceMotion);
    media.addEventListener("change", apply);
    return () => media.removeEventListener("change", apply);
  }, [settings.theme, settings.reduceMotion]);

  const serverLanguage = session.phase === "signed-in" ? session.connection.serverLanguage : undefined;
  const language = hydrated
    ? (settings.language ?? (isLanguageCode(serverLanguage) ? serverLanguage : "en-us"))
    : initialLanguage.code;

  return (
    <QueryClientProvider client={queryClient}>
      <I18nProvider code={language} initialLanguage={initialLanguage}>
        {children}
      </I18nProvider>
    </QueryClientProvider>
  );
}
