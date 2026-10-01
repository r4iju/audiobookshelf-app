"use client";

import ePub, { type Book, type Contents, type NavItem, type Rendition } from "epubjs";
import { List, Settings2 } from "lucide-react";
import { useEffect, useEffectEvent, useRef, useState } from "react";
import { z } from "zod";
import { Button } from "@/components/ui/button";
import { Dialog } from "@/components/ui/dialog";
import { Alert, Spinner } from "@/components/ui/status";
import { useI18n } from "@/i18n/i18n";
import { type ReaderSettings, useSettings } from "@/lib/settings/store";
import { keepLocations, storedLocations } from "@/lib/storage/epub-locations";
import { ReaderBar, turnForKey, usePageKeys, useSwipe } from "./paging";
import type { ReaderViewProps } from "./reader";
import { ReaderSettingsDialog } from "./reader-settings";

const themes: Record<ReaderSettings["theme"], { color: string; background: string }> = {
  dark: { color: "#fff", background: "rgb(35, 35, 35)" },
  black: { color: "#fff", background: "rgb(0, 0, 0)" },
  light: { color: "#000", background: "rgb(255, 255, 255)" },
};

/** The legacy reader's rules, so a book looks the same in every client. */
function themeCss(settings: ReaderSettings) {
  const { color, background } = themes[settings.theme];
  return `* { color: ${color} !important; background-color: ${background} !important; line-height: ${settings.lineSpacing}% !important; -webkit-text-stroke: ${settings.textStroke / 100}px ${color} !important; }
a { color: ${color} !important; }`;
}

/** epub.js's own theme rules cannot be replaced, only added to, so the colours live in one style element per section. */
function applyTheme(contents: Contents, settings: ReaderSettings) {
  const document = contents.document;
  let style = document.getElementById("abs-reader-theme");
  if (!style) {
    style = document.createElement("style");
    style.id = "abs-reader-theme";
    document.head.append(style);
  }
  style.textContent = themeCss(settings);
}

const LOCATION_CHARS = 100;

async function loadLocations(book: Book, cacheKey: string) {
  const stored = storedLocations(cacheKey);
  if (stored) {
    book.locations.load(stored);
    return;
  }
  await book.locations.generate(LOCATION_CHARS);
  keepLocations(cacheKey, book.locations.save());
}

/** A saved place opens the book only if it is a CFI into this book, as in the legacy reader. */
function openingPlace(book: Book, saved: string | null) {
  if (!saved?.startsWith("epubcfi")) return undefined;
  try {
    return book.spine.get(saved) ? saved : undefined;
  } catch {
    return undefined;
  }
}

/** epub.js fills in location numbers and percentages once locations exist; its typings leave them out. */
const placeSchema = z.object({
  start: z.object({ cfi: z.string(), location: z.number().optional() }),
  end: z.object({ percentage: z.number().optional() }),
});

interface Chapter {
  key: string;
  label: string;
  href: string;
  depth: number;
}

function chapters(toc: NavItem[], depth = 0, parent = ""): Chapter[] {
  return toc.flatMap((entry, index) => {
    const key = `${parent}${index}`;
    return [
      { key, label: entry.label.trim(), href: entry.href, depth },
      ...chapters(entry.subitems ?? [], depth + 1, `${key}.`),
    ];
  });
}

type Opened =
  | { phase: "loading" }
  | { phase: "failed" }
  | { phase: "ready"; rendition: Rendition; chapters: Chapter[] };

/** Mounted once per document: the reader keys it by the file it shows. */
export function EpubView({ file, start, onPlace, cacheKey }: ReaderViewProps) {
  const { t } = useI18n();
  const settings = useSettings().reader;
  const stage = useRef<HTMLDivElement>(null);
  const [opened, setOpened] = useState<Opened>({ phase: "loading" });
  const [location, setLocation] = useState<{ at: number; of: number } | null>(null);
  const [dialog, setDialog] = useState<"contents" | "settings" | null>(null);
  const rendition = opened.phase === "ready" ? opened.rendition : null;

  const turns = {
    next: () => void rendition?.next(),
    previous: () => void rendition?.prev(),
  };
  usePageKeys(turns);
  const swipe = useSwipe(turns);

  const savedPlace = useEffectEvent(() => start);
  const onShown = useEffectEvent((reported: unknown, locations: number) => {
    const place = placeSchema.safeParse(reported);
    if (!place.success) return null;
    const { start: from, end } = place.data;
    setLocation(locations && from.location !== undefined ? { at: from.location + 1, of: locations } : null);
    return { ebookLocation: from.cfi, ebookProgress: end.percentage };
  });
  const save = useEffectEvent(
    ({ ebookLocation, ebookProgress }: { ebookLocation: string; ebookProgress?: number }) =>
      // Like the legacy reader, a zero or unknown progress is left out so it never clears the server's.
      onPlace({ ebookLocation, ...(ebookProgress ? { ebookProgress } : {}) }),
  );
  const onSectionShown = useEffectEvent((contents: Contents) => applyTheme(contents, settings));
  const onFrameKey = useEffectEvent((event: KeyboardEvent) => turnForKey(event, turns));

  // External system: epub.js unpacks the book and lays it out in its own frame. Each run owns its
  // book, because a rendition leaves hooks on the book that outlive the rendition.
  useEffect(() => {
    const element = stage.current;
    if (!element) return;
    let current = true;
    const book = ePub();
    const opening = file
      .arrayBuffer()
      .then((data) => book.open(data, "binary"))
      .then(() => Promise.all([book.opened, book.ready]));
    const shown = opening
      .then(async () => {
        if (!current) return;
        const view = book.renderTo(element, {
          width: "100%",
          height: "100%",
          flow: "paginated",
          spread: "auto",
        });
        let lastSaved = savedPlace();
        let located = false;
        let movedEarly = false;
        view.on("relocated", (reported: unknown) => {
          const place = onShown(reported, book.locations.length());
          if (!place || place.ebookLocation === lastSaved) return;
          lastSaved = place.ebookLocation;
          if (located) save(place);
          else movedEarly = true;
        });
        view.on("keydown", (event: KeyboardEvent) => onFrameKey(event));
        view.hooks.content.register((contents: Contents) => onSectionShown(contents));
        setOpened({ phase: "ready", rendition: view, chapters: chapters(book.navigation.toc) });
        await view.display(openingPlace(book, savedPlace()));
        await loadLocations(book, cacheKey);
        if (!current) return;
        located = true;
        // A place reached before the locations existed is saved now, with its progress.
        const place = onShown(view.currentLocation(), book.locations.length());
        if (movedEarly && place) save(place);
      })
      .catch(() => current && setOpened({ phase: "failed" }));
    return () => {
      current = false;
      // Tearing a book down while epub.js is still working on it throws inside epub.js.
      void shown.finally(() => book.destroy());
    };
  }, [file, cacheKey]);

  // External system: the open sections take the reader's display settings.
  useEffect(() => {
    if (!rendition) return;
    rendition.themes.fontSize(`${settings.fontScale}%`);
    rendition.themes.font(settings.font);
    rendition.spread(settings.spread);
    // The typings declare one Contents; epub.js returns one per displayed section.
    for (const contents of rendition.getContents() as unknown as Contents[]) applyTheme(contents, settings);
  }, [rendition, settings]);

  return (
    <>
      <div className="relative min-h-0 flex-1" style={{ background: themes[settings.theme].background }}>
        <div ref={stage} className="absolute inset-0 px-2 py-4 sm:px-8" {...swipe} />
        {opened.phase === "loading" ? (
          <div className="absolute inset-0 bg-bg">
            <Spinner label={t("WebLoading")} />
          </div>
        ) : opened.phase === "failed" ? (
          <div className="absolute inset-0 bg-bg">
            <Alert>{t("WebDocumentUnreadable")}</Alert>
          </div>
        ) : null}
      </div>
      {opened.phase === "ready" ? (
        <ReaderBar onPrevious={turns.previous} onNext={turns.next}>
          <div className="flex items-center gap-1">
            <Button
              variant="ghost"
              size="icon"
              aria-label={t("HeaderTableOfContents")}
              onClick={() => setDialog("contents")}
            >
              <List aria-hidden className="size-5" />
            </Button>
            <output aria-live="polite" className="min-w-32 text-center text-sm text-muted tabular-nums">
              {location ? t("WebReaderLocation", location.at, location.of) : null}
            </output>
            <Button
              variant="ghost"
              size="icon"
              aria-label={t("WebReaderSettings")}
              onClick={() => setDialog("settings")}
            >
              <Settings2 aria-hidden className="size-5" />
            </Button>
          </div>
        </ReaderBar>
      ) : null}

      {dialog === "contents" && opened.phase === "ready" ? (
        <Dialog open onClose={() => setDialog(null)} title={t("HeaderTableOfContents")}>
          {opened.chapters.length ? (
            <ul className="-mx-2 flex max-h-[60vh] flex-col gap-0.5 overflow-y-auto">
              {opened.chapters.map((chapter) => (
                <li key={chapter.key}>
                  <button
                    type="button"
                    className="w-full rounded-lg px-3 py-2 text-start text-sm hover:bg-surface-2 focus-ring"
                    style={{ paddingInlineStart: `${0.75 + chapter.depth}rem` }}
                    onClick={() => {
                      setDialog(null);
                      void opened.rendition.display(chapter.href);
                    }}
                  >
                    {chapter.label}
                  </button>
                </li>
              ))}
            </ul>
          ) : (
            <p className="text-sm text-muted">{t("MessageNoChapters")}</p>
          )}
          <div className="flex justify-end">
            <Button variant="ghost" onClick={() => setDialog(null)}>
              {t("WebClose")}
            </Button>
          </div>
        </Dialog>
      ) : null}
      {dialog === "settings" ? <ReaderSettingsDialog onClose={() => setDialog(null)} /> : null}
    </>
  );
}
