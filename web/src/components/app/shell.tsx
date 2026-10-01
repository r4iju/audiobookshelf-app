"use client";

import {
  BarChart3,
  BookOpen,
  Headphones,
  Home,
  Library as LibraryIcon,
  ListMusic,
  LogOut,
  Mic,
  Rss,
  Search,
  Settings,
  Users,
  WifiOff,
} from "lucide-react";
import Link from "next/link";
import { useParams, usePathname, useRouter } from "next/navigation";
import { type ReactNode, useEffect } from "react";
import { AudioEngine } from "@/components/player/audio-engine";
import { PlayerDock } from "@/components/player/player-dock";
import { ButtonLink } from "@/components/ui/button";
import { Alert, Spinner } from "@/components/ui/status";
import { type StringKey, useI18n } from "@/i18n/i18n";
import { useLibraries } from "@/lib/abs/queries";
import type { Library } from "@/lib/abs/schemas";
import { usePlayer } from "@/lib/player/store";
import * as registry from "@/lib/session/registry";
import { useSession, useSessionStore } from "@/lib/session/store";
import { errorMessage } from "./errors";
import { useOnline } from "./online";

export function SignedInShell({ children }: { children: ReactNode }) {
  const session = useSession();
  const router = useRouter();
  const { t } = useI18n();

  // External system: routing; a signed-out browser belongs on the connect screen.
  useEffect(() => {
    if (session.phase === "signed-out") router.replace("/connect");
  }, [session.phase, router]);

  if (session.phase !== "signed-in") return <Spinner label={t("WebLoading")} />;
  return <Shell key={session.connection.id}>{children}</Shell>;
}

type Section = {
  key: string;
  href: (libraryId: string) => string;
  label: StringKey;
  icon: typeof Home;
  for: Library["mediaType"] | "any";
};

const sections: Section[] = [
  { key: "home", href: (id) => `/library/${id}`, label: "WebHome", icon: Home, for: "any" },
  {
    key: "items",
    href: (id) => `/library/${id}/items`,
    label: "ButtonLibrary",
    icon: LibraryIcon,
    for: "any",
  },
  { key: "latest", href: (id) => `/library/${id}/latest`, label: "ButtonLatest", icon: Rss, for: "podcast" },
  {
    key: "series",
    href: (id) => `/library/${id}/series`,
    label: "ButtonSeries",
    icon: BookOpen,
    for: "book",
  },
  {
    key: "authors",
    href: (id) => `/library/${id}/authors`,
    label: "ButtonAuthors",
    icon: Users,
    for: "book",
  },
  {
    key: "collections",
    href: (id) => `/library/${id}/collections`,
    label: "ButtonCollections",
    icon: ListMusic,
    for: "book",
  },
  {
    key: "playlists",
    href: (id) => `/library/${id}/playlists`,
    label: "ButtonPlaylists",
    icon: ListMusic,
    for: "any",
  },
  { key: "search", href: (id) => `/library/${id}/search`, label: "ButtonSearch", icon: Search, for: "any" },
];

function navClass(active: boolean) {
  return `flex min-h-10 items-center gap-3 rounded-lg px-3 text-sm font-medium focus-ring ${active ? "bg-surface-2 text-fg" : "text-muted hover:bg-surface-2 hover:text-fg"}`;
}

function Shell({ children }: { children: ReactNode }) {
  const { t } = useI18n();
  const session = useSession();
  const signOut = useSessionStore((state) => state.signOut);
  const router = useRouter();
  const pathname = usePathname();
  const params = useParams<{ libraryId?: string }>();
  const libraries = useLibraries();
  const online = useOnline();
  const playerActive = usePlayer().phase === "active";

  if (session.phase !== "signed-in") return null;
  const { connection } = session;
  const list = libraries.data ?? [];
  const remembered = registry.lastLibraryId(connection.id);
  const current =
    list.find((library) => library.id === params.libraryId) ??
    list.find((library) => library.id === remembered) ??
    list[0];
  const reauthHref = `/connect?${new URLSearchParams({ server: connection.serverUrl, username: connection.username })}`;

  return (
    <div className="min-h-dvh lg:grid lg:grid-cols-[15rem_1fr]">
      <a
        href="#main"
        className="sr-only focus:not-sr-only focus:fixed focus:top-2 focus:left-2 focus:z-50 focus:rounded-lg focus:bg-surface focus:px-4 focus:py-2"
      >
        {t("WebSkipToContent")}
      </a>
      <aside className="border-line lg:sticky lg:top-0 lg:flex lg:h-dvh lg:flex-col lg:gap-6 lg:overflow-y-auto lg:border-r lg:px-3 lg:py-5">
        <div className="flex items-center justify-between gap-3 px-4 pt-4 lg:px-3 lg:pt-0">
          <Link href="/" className="flex items-center gap-2 rounded-lg font-bold focus-ring">
            <span
              aria-hidden
              className="grid size-8 place-items-center rounded-lg bg-accent-strong text-accent-fg"
            >
              <Headphones className="size-4" />
            </span>
            {t("WebAppName")}
          </Link>
          <div className="flex items-center gap-1 lg:hidden">
            <ButtonLink href="/settings" variant="ghost" size="icon" aria-label={t("HeaderSettings")}>
              <Settings aria-hidden className="size-5" />
            </ButtonLink>
          </div>
        </div>

        <nav aria-label={t("WebNavLibrary")} className="px-4 pt-3 lg:px-0 lg:pt-0">
          {libraries.isPending ? (
            <p className="px-3 text-sm text-muted">{t("WebLoading")}</p>
          ) : libraries.isError ? (
            <p className="px-3 text-sm text-danger">{errorMessage(t, libraries.error)}</p>
          ) : (
            <ul className="flex gap-2 overflow-x-auto pb-1 lg:flex-col lg:gap-0.5 lg:overflow-visible">
              {list.map((library) => {
                const Icon = library.mediaType === "podcast" ? Mic : BookOpen;
                const active = library.id === current?.id;
                return (
                  <li key={library.id} className="shrink-0">
                    <Link
                      href={`/library/${library.id}`}
                      aria-current={active ? "true" : undefined}
                      className={`${navClass(active)} max-lg:rounded-full max-lg:border max-lg:border-line ${active ? "max-lg:border-accent" : ""}`}
                    >
                      <Icon aria-hidden className="size-4 shrink-0" />
                      <span className="truncate">{library.name}</span>
                    </Link>
                  </li>
                );
              })}
            </ul>
          )}
        </nav>

        {current ? (
          <nav
            aria-label={t("WebNavPrimary")}
            className="max-lg:fixed max-lg:inset-x-0 max-lg:bottom-0 max-lg:z-30 max-lg:border-t max-lg:border-line max-lg:bg-surface/95 max-lg:pb-[env(safe-area-inset-bottom)] max-lg:backdrop-blur"
          >
            <ul className="flex justify-around lg:flex-col lg:gap-0.5">
              {sections
                .filter((section) => section.for === "any" || section.for === current.mediaType)
                .map((section) => {
                  const href = section.href(current.id);
                  const active = section.key === "home" ? pathname === href : pathname.startsWith(href);
                  const Icon = section.icon;
                  const mobileHidden =
                    section.key === "authors" || section.key === "collections" || section.key === "playlists";
                  return (
                    <li key={section.key} className={mobileHidden ? "max-lg:hidden" : undefined}>
                      <Link
                        href={href}
                        aria-current={active ? "page" : undefined}
                        className={`${navClass(active)} max-lg:min-h-14 max-lg:flex-col max-lg:justify-center max-lg:gap-0.5 max-lg:bg-transparent max-lg:px-2 max-lg:text-[0.7rem] ${active ? "max-lg:text-accent" : ""}`}
                      >
                        <Icon aria-hidden className="size-5 shrink-0 lg:size-4" />
                        {t(section.label)}
                      </Link>
                    </li>
                  );
                })}
            </ul>
          </nav>
        ) : null}

        <div className="mt-auto hidden flex-col gap-0.5 lg:flex">
          <Link href="/stats" className={navClass(pathname === "/stats")}>
            <BarChart3 aria-hidden className="size-4" />
            {t("WebStats")}
          </Link>
          <Link href="/settings" className={navClass(pathname.startsWith("/settings"))}>
            <Settings aria-hidden className="size-4" />
            {t("HeaderSettings")}
          </Link>
          <div className="mt-2 flex items-center gap-2 rounded-lg bg-surface px-3 py-2">
            <div className="min-w-0 flex-1">
              <p className="truncate text-sm font-semibold">{connection.username}</p>
              <p className="truncate text-xs text-muted">{new URL(connection.serverUrl).host}</p>
            </div>
            <button
              type="button"
              onClick={() => {
                signOut();
                router.replace("/connect");
              }}
              aria-label={t("WebSignOut")}
              className="grid size-9 place-items-center rounded-lg text-muted hover:bg-surface-2 hover:text-fg focus-ring"
            >
              <LogOut aria-hidden className="size-4" />
            </button>
          </div>
        </div>
      </aside>

      <div className={`flex min-w-0 flex-col ${playerActive ? "pb-56 lg:pb-44" : "pb-24 lg:pb-8"}`}>
        <div className="flex flex-col gap-2 px-4 pt-4 empty:hidden lg:px-8">
          {session.reauthRequired ? (
            <Alert
              action={
                <ButtonLink href={reauthHref} size="sm" variant="primary">
                  {t("WebSignIn")}
                </ButtonLink>
              }
            >
              {t("WebReauthRequired")}
            </Alert>
          ) : null}
          {online ? null : (
            <Alert tone="info">
              <span className="inline-flex items-center gap-2">
                <WifiOff aria-hidden className="size-4" />
                {t("WebOffline")}
              </span>
            </Alert>
          )}
        </div>
        <main id="main" tabIndex={-1} className="flex-1 px-4 py-5 outline-none lg:px-8 lg:py-8">
          {children}
        </main>
      </div>
      <AudioEngine />
      <PlayerDock />
    </div>
  );
}
