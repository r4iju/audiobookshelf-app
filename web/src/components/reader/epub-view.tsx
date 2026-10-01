"use client";

import ePub, { type Book, type Contents, type Rendition } from "epubjs";
import { useEffect, useEffectEvent, useRef, useState } from "react";
import { z } from "zod";
import { Alert, Spinner } from "@/components/ui/status";
import { useI18n } from "@/i18n/i18n";
import { useSettings } from "@/lib/settings/store";
import { keepLocations, storedLocations } from "@/lib/storage/epub-locations";
import { applyReaderCss, readerCss, readerThemes } from "./book-theme";
import { BookControls, type Chapter, ContentsDialog, flattenToc } from "./contents";
import { ReaderBar, turnForKey, usePageKeys, useSwipe } from "./paging";
import type { ReaderViewProps } from "./reader";
import { ReaderSettingsDialog } from "./reader-settings";

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
  const onSectionShown = useEffectEvent((contents: Contents) =>
    applyReaderCss(contents.document, readerCss(settings)),
  );
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
        setOpened({ phase: "ready", rendition: view, chapters: flattenToc(book.navigation.toc) });
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
    for (const contents of rendition.getContents() as unknown as Contents[])
      applyReaderCss(contents.document, readerCss(settings));
  }, [rendition, settings]);

  return (
    <>
      <div
        className="relative min-h-0 flex-1"
        style={{ background: readerThemes[settings.theme].background }}
      >
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
          <BookControls
            status={location ? t("WebReaderLocation", location.at, location.of) : null}
            onContents={() => setDialog("contents")}
            onSettings={() => setDialog("settings")}
          />
        </ReaderBar>
      ) : null}

      {dialog === "contents" && opened.phase === "ready" ? (
        <ContentsDialog
          chapters={opened.chapters}
          onPick={(chapter) => void opened.rendition.display(chapter.href)}
          onClose={() => setDialog(null)}
        />
      ) : null}
      {dialog === "settings" ? <ReaderSettingsDialog paged onClose={() => setDialog(null)} /> : null}
    </>
  );
}
