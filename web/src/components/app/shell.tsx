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
  PlusCircle,
  Rss,
  Search,
  Settings,
  Users,
  WifiOff,
} from "lucide-react";
import Link from "next/link";
import { useParams, usePathname, useRouter } from "next/navigation";
import { type ReactNode, useEffect, useRef } from "react";
import { HeldDeliveries } from "@/components/app/held-deliveries";
import { AudioEngine } from "@/components/player/audio-engine";
import { PlayerDock } from "@/components/player/player-dock";
import { ButtonLink } from "@/components/ui/button";
import { Alert, Spinner } from "@/components/ui/status";
import { type StringKey, useI18n } from "@/i18n/i18n";
import { isAdmin } from "@/lib/abs/permissions";
import { useLibraries, useMe } from "@/lib/abs/queries";
import type { Library } from "@/lib/abs/schemas";
import { useCurrentLibrary } from "@/lib/session/current-library";
import * as registry from "@/lib/session/registry";
import { useSession, useSessionStore } from "@/lib/session/store";
import { errorMessage } from "./errors";
import { useOnline } from "./online";
import { useKeyboardScrolling, useScrollRestoration } from "./page-scroller";
import { useHeadingTitle } from "./page-title";
import { useRealtime } from "./realtime";

export function SignedInShell({ children }: { children: ReactNode }) {
  const session = useSession();
  const router = useRouter();
  const { t } = useI18n();

  // External system: routing; a signed-out browser belongs on the connect screen.
  useEffect(() => {
    if (session.phase === "signed-out") router.replace("/connect");
  }, [session.phase, router]);

  if (session.phase !== "signed-in") return <Spinner label={t("MessageLoading")} />;
  return <Shell key={session.connection.id}>{children}</Shell>;
}

type Section = {
  key: string;
  href: (libraryId: string) => string;
  label: StringKey;
  icon: typeof Home;
  for: Library["mediaType"] | "any";
  adminOnly?: true;
  /** Where the section sits on phones: the bottom bar or the scrolling row under the libraries. */
  phone: "bar" | "more";
};

const sections: Section[] = [
  { key: "home", phone: "bar", href: (id) => `/library/${id}`, label: "ButtonHome", icon: Home, for: "any" },
  {
    key: "items",
    phone: "bar",
    href: (id) => `/library/${id}/items`,
    label: "ButtonLibrary",
    icon: LibraryIcon,
    for: "any",
  },
  {
    key: "latest",
    phone: "bar",
    href: (id) => `/library/${id}/latest`,
    label: "ButtonLatest",
    icon: Rss,
    for: "podcast",
  },
  {
    key: "series",
    phone: "bar",
    href: (id) => `/library/${id}/series`,
    label: "ButtonSeries",
    icon: BookOpen,
    for: "book",
  },
  {
    key: "authors",
    phone: "more",
    href: (id) => `/library/${id}/authors`,
    label: "ButtonAuthors",
    icon: Users,
    for: "book",
  },
  {
    key: "collections",
    phone: "more",
    href: (id) => `/library/${id}/collections`,
    label: "ButtonCollections",
    icon: ListMusic,
    for: "book",
  },
  {
    key: "playlists",
    phone: "more",
    href: (id) => `/library/${id}/playlists`,
    label: "ButtonPlaylists",
    icon: ListMusic,
    for: "any",
  },
  {
    key: "search",
    phone: "bar",
    href: (id) => `/library/${id}/search`,
    label: "ButtonSearch",
    icon: Search,
    for: "any",
  },
  {
    key: "add-podcast",
    phone: "more",
    href: (id) => `/library/${id}/add-podcast`,
    label: "WebAddPodcast",
    icon: PlusCircle,
    for: "podcast",
    adminOnly: true,
  },
];

function navClass(active: boolean) {
  return `flex min-h-10 items-center gap-3 rounded-lg px-3 text-sm font-medium focus-ring ${active ? "bg-surface-2 text-fg" : "text-muted hover:bg-surface-2 hover:text-fg"}`;
}

function chipClass(active: boolean) {
  return `flex min-h-10 items-center gap-2 rounded-full border px-3 text-sm font-medium focus-ring ${active ? "border-accent bg-surface-2 text-fg" : "border-line text-muted hover:bg-surface-2 hover:text-fg"}`;
}

/** A phone row that scrolls to the screen's edges while its first and last chips line up with the page. */
const chipRow = "flex gap-2 overflow-x-auto scroll-px-4 px-4 pb-1";

function Shell({ children }: { children: ReactNode }) {
  const { t } = useI18n();
  const session = useSession();
  const signOut = useSessionStore((state) => state.signOut);
  const router = useRouter();
  const pathname = usePathname();
  const params = useParams<{ libraryId?: string }>();
  useHeadingTitle();
  const libraries = useLibraries();
  const admin = isAdmin(useMe().data);
  const shownLibrary = useCurrentLibrary((state) => state.libraryId);
  const online = useOnline();
  useRealtime();
  const scroller = useRef<HTMLDivElement>(null);
  useScrollRestoration(scroller, !pathname.startsWith("/read/"));
  useKeyboardScrolling(scroller, !pathname.startsWith("/read/"));

  if (session.phase !== "signed-in") return null;
  const { connection } = session;
  const list = libraries.data ?? [];
  const remembered = registry.lastLibraryId(connection.id);
  const current =
    list.find((library) => library.id === params.libraryId) ??
    list.find((library) => library.id === shownLibrary) ??
    list.find((library) => library.id === remembered) ??
    list[0];
  const visible = current
    ? sections.filter(
        (section) =>
          (section.for === "any" || section.for === current.mediaType) && (!section.adminOnly || admin),
      )
    : [];
  const phoneMore = visible.filter((section) => section.phone === "more");
  const isActive = (section: Section, href: string) =>
    section.key === "home" ? pathname === href : pathname.startsWith(href);
  const reauthHref = `/connect?${new URLSearchParams({ server: connection.serverUrl, username: connection.username, next: pathname })}`;

  const reading = pathname.startsWith("/read/");

  const libraryLinks = (chips: boolean) =>
    libraries.isPending ? (
      <p className="px-3 text-sm text-muted">{t("MessageLoading")}</p>
    ) : libraries.isError ? (
      <p className="px-3 text-sm text-danger">{errorMessage(t, libraries.error)}</p>
    ) : (
      <ul className={chips ? chipRow : "flex flex-col gap-0.5"}>
        {list.map((library) => {
          const Icon = library.mediaType === "podcast" ? Mic : BookOpen;
          const active = library.id === current?.id;
          return (
            <li key={library.id} className="shrink-0">
              <Link
                href={`/library/${library.id}`}
                aria-current={active ? "true" : undefined}
                className={chips ? chipClass(active) : navClass(active)}
              >
                <Icon aria-hidden className="size-4 shrink-0" />
                <span className="truncate">{library.name}</span>
              </Link>
            </li>
          );
        })}
      </ul>
    );
  const brand = (
    <Link href="/" className="flex items-center gap-2 rounded-lg font-bold focus-ring">
      <span aria-hidden className="grid size-8 place-items-center rounded-lg bg-accent-strong text-accent-fg">
        <Headphones className="size-4" />
      </span>
      {t("WebAppName")}
    </Link>
  );

  // The audio engine and dock keep one place in the tree so playback carries on into and out of the reader. The
  // page scrolls in its own box above the dock and the phone's bar, so neither covers the page or its scrollbar.
  return (
    <div
      className={reading ? "flex h-dvh flex-col" : "flex h-dvh lg:grid lg:grid-cols-[15rem_minmax(0,1fr)]"}
    >
      {reading ? null : (
        <a
          href="#main"
          className="sr-only focus:not-sr-only focus:fixed focus:top-2 focus:left-2 focus:z-50 focus:rounded-lg focus:bg-surface focus:px-4 focus:py-2"
        >
          {t("WebSkipToContent")}
        </a>
      )}
      {reading ? null : (
        <aside className="hidden border-line lg:flex lg:flex-col lg:gap-6 lg:overflow-y-auto lg:border-r lg:px-3 lg:py-5">
          <div className="px-3">{brand}</div>
          <nav aria-label={t("WebNavLibrary")}>{libraryLinks(false)}</nav>
          {current ? (
            <nav aria-label={t("WebNavPrimary")}>
              <ul className="flex flex-col gap-0.5">
                {visible.map((section) => {
                  const href = section.href(current.id);
                  const Icon = section.icon;
                  return (
                    <li key={section.key}>
                      <Link
                        href={href}
                        aria-current={isActive(section, href) ? "page" : undefined}
                        className={navClass(isActive(section, href))}
                      >
                        <Icon aria-hidden className="size-4 shrink-0" />
                        {t(section.label)}
                      </Link>
                    </li>
                  );
                })}
              </ul>
            </nav>
          ) : null}
          <div className="mt-auto flex flex-col gap-0.5">
            {admin ? (
              <Link href="/admin/libraries" className={navClass(pathname.startsWith("/admin/libraries"))}>
                <LibraryIcon aria-hidden className="size-4" />
                Manage libraries
              </Link>
            ) : null}
            {admin ? (
              <>
                <Link href="/admin/server" className={navClass(pathname.startsWith("/admin/server"))}>
                  <LibraryIcon aria-hidden className="size-4" />
                  Server settings
                </Link>
                <Link href="/admin/openid" className={navClass(pathname.startsWith("/admin/openid"))}>
                  <LibraryIcon aria-hidden className="size-4" />
                  OpenID sign-in
                </Link>
                <Link href="/admin/delivery" className={navClass(pathname.startsWith("/admin/delivery"))}>
                  <LibraryIcon aria-hidden className="size-4" />
                  E-reader delivery
                </Link>
              </>
            ) : null}
            {admin ? (
              <Link href="/admin/podcasts" className={navClass(pathname.startsWith("/admin/podcasts"))}>
                <LibraryIcon aria-hidden className="size-4" />
                Podcast settings
              </Link>
            ) : null}
            {admin ? (
              <Link href="/admin/migration" className={navClass(pathname.startsWith("/admin/migration"))}>
                <Users aria-hidden className="size-4" />
                Migration and backups
              </Link>
            ) : null}
            {admin ? (
              <Link href="/admin/accounts" className={navClass(pathname.startsWith("/admin/accounts"))}>
                <Users aria-hidden className="size-4" />
                Accounts
              </Link>
            ) : null}
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
      )}
      <div className="flex min-h-0 min-w-0 flex-1 flex-col">
        {reading ? (
          <main id="main" tabIndex={-1} className="min-h-0 flex-1 outline-none">
            {children}
          </main>
        ) : (
          <div ref={scroller} className="min-h-0 flex-1 overflow-y-auto">
            <header className="flex flex-col gap-2 pt-4 lg:hidden">
              <div className="flex items-center justify-between gap-3 px-4">
                {brand}
                <div className="flex items-center gap-1">
                  {admin ? (
                    <ButtonLink href="/admin/accounts" variant="ghost" size="icon" aria-label="Accounts">
                      <Users aria-hidden className="size-5" />
                    </ButtonLink>
                  ) : null}
                  <ButtonLink href="/stats" variant="ghost" size="icon" aria-label={t("WebStats")}>
                    <BarChart3 aria-hidden className="size-5" />
                  </ButtonLink>
                  <ButtonLink href="/settings" variant="ghost" size="icon" aria-label={t("HeaderSettings")}>
                    <Settings aria-hidden className="size-5" />
                  </ButtonLink>
                </div>
              </div>
              <nav aria-label={t("WebNavLibrary")} className="pt-1">
                {libraryLinks(true)}
              </nav>
              {current && phoneMore.length ? (
                // The phone's bottom bar has room for four sections; the rest scroll in a row under the libraries.
                <nav aria-label={t("WebMore")}>
                  <ul className={chipRow}>
                    {phoneMore.map((section) => {
                      const href = section.href(current.id);
                      const Icon = section.icon;
                      return (
                        <li key={section.key} className="shrink-0">
                          <Link
                            href={href}
                            aria-current={isActive(section, href) ? "page" : undefined}
                            className={chipClass(isActive(section, href))}
                          >
                            <Icon aria-hidden className="size-4 shrink-0" />
                            {t(section.label)}
                          </Link>
                        </li>
                      );
                    })}
                  </ul>
                </nav>
              ) : null}
            </header>
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
              <HeldDeliveries />
              {online ? null : (
                <Alert tone="info">
                  <span className="inline-flex items-center gap-2">
                    <WifiOff aria-hidden className="size-4" />
                    {t("WebOffline")}
                  </span>
                </Alert>
              )}
            </div>
            <main id="main" tabIndex={-1} className="px-4 py-5 outline-none lg:px-8 lg:py-8">
              {children}
            </main>
          </div>
        )}
        <PlayerDock fullWindow={reading} />
        {reading || !current ? null : (
          <nav
            aria-label={t("WebNavPrimary")}
            className="border-t border-line bg-surface pb-[env(safe-area-inset-bottom)] lg:hidden"
          >
            <ul className="flex justify-around">
              {visible
                .filter((section) => section.phone === "bar")
                .map((section) => {
                  const href = section.href(current.id);
                  const Icon = section.icon;
                  const active = isActive(section, href);
                  return (
                    <li key={section.key}>
                      <Link
                        href={href}
                        aria-current={active ? "page" : undefined}
                        className={`flex min-h-14 flex-col items-center justify-center gap-0.5 rounded-lg px-2 text-[0.7rem] font-medium focus-ring ${active ? "text-accent" : "text-muted hover:text-fg"}`}
                      >
                        <Icon aria-hidden className="size-5 shrink-0" />
                        {t(section.label)}
                      </Link>
                    </li>
                  );
                })}
            </ul>
          </nav>
        )}
      </div>
      <AudioEngine />
    </div>
  );
}
