"use client";

import { isMOBI, MOBI, type MobiBook } from "foliate-js/mobi.js";
import { unzlibSync } from "foliate-js/vendor/fflate.js";
import { useEffect, useEffectEvent, useLayoutEffect, useRef, useState } from "react";
import { Alert, Spinner } from "@/components/ui/status";
import { useI18n } from "@/i18n/i18n";
import { mobiLocation, mobiPlace, mobiProgress } from "@/lib/abs/ebooks";
import type { EbookPlace } from "@/lib/abs/mutations";
import { type ReaderSettings, useSettings } from "@/lib/settings/store";
import { applyReaderCss, readerCss, readerThemes } from "./book-theme";
import { BookControls, type Chapter, ContentsDialog, flattenToc } from "./contents";
import { ReaderBar, turnForKey, usePageKeys } from "./paging";
import type { ReaderViewProps } from "./reader";
import { ReaderSettingsDialog } from "./reader-settings";

/** The elements a saved place counts through to find its passage again; only the innermost ones count. */
const BLOCKS = "p, h1, h2, h3, h4, h5, h6, li, blockquote, pre, figure, img, table, dt, dd";
/** How much of one screen stays in view after turning to the next, so no line is lost between them. */
const OVERLAP = 48;
/** Room left above a passage the reader is taken to. */
const LEAD = 16;
const XLINK = "http://www.w3.org/1999/xlink";
/** Where a book's link really points, kept on the link while its own href becomes a fragment of the section. */
const LINK = "data-abs-href";
const LINK_FRAGMENT = "#abs-link-";

type Spot = { block: number } | { edge: "start" | "end" } | { anchor: (doc: Document) => Element | null };
interface Target {
  section: number;
  spot: Spot;
  /** Whether arriving there is the reader's own move, to be saved, rather than reopening a saved place. */
  moved: boolean;
}

type Opened =
  | { phase: "loading" }
  | { phase: "failed" }
  | { phase: "ready"; book: MobiBook; readable: number[]; sizes: number[]; chapters: Chapter[] };

function mobiCss(settings: ReaderSettings) {
  return `${readerCss(settings)}
html { font-size: ${settings.fontScale}% !important; }
body { font-family: ${settings.font} !important; max-width: 42rem; margin: 0 auto !important; padding: 1.5rem 1.25rem 3rem !important; }
img { max-width: 100%; height: auto; }`;
}

const blockCache = new WeakMap<Document, Element[]>();
function blocksOf(doc: Document) {
  let blocks = blockCache.get(doc);
  if (!blocks) {
    blocks = Array.from(doc.body.querySelectorAll(BLOCKS)).filter((block) => !block.querySelector(BLOCKS));
    blockCache.set(doc, blocks);
  }
  return blocks;
}

/**
 * Points each link at a fragment of its own section, keeping where it really points. Following one then only changes
 * the section's address, which the reader sees without the book running a script or sending it an event.
 */
function routeLinks(doc: Document) {
  doc.querySelectorAll("a").forEach((link, index) => {
    const href = link.getAttribute("href") ?? link.getAttributeNS(XLINK, "href");
    if (!href || link.hasAttribute(LINK)) return;
    link.setAttribute(LINK, href);
    if (link.hasAttribute("href")) link.setAttribute("href", `${LINK_FRAGMENT}${index}`);
    else link.setAttributeNS(XLINK, "href", `${LINK_FRAGMENT}${index}`);
  });
}

const withoutFragment = (url: string) => url.split("#")[0];

/** Scrolls the section to a spot, reporting whether it moved. */
function scrollTo(doc: Document, spot: Spot) {
  const scroller = doc.scrollingElement;
  if (!scroller) return false;
  const before = scroller.scrollTop;
  const top = (element: Element | null | undefined) =>
    element ? element.getBoundingClientRect().top + scroller.scrollTop - LEAD : 0;
  if ("edge" in spot) scroller.scrollTop = spot.edge === "end" ? scroller.scrollHeight : 0;
  else if ("anchor" in spot) scroller.scrollTop = top(spot.anchor(doc));
  else scroller.scrollTop = top(blocksOf(doc)[spot.block]);
  return scroller.scrollTop !== before;
}

/** The first passage not yet scrolled past the lead space, and the share of the section read so far. */
function placeIn(doc: Document) {
  const blocks = blocksOf(doc);
  let [low, high] = [0, blocks.length - 1];
  while (low < high) {
    const middle = Math.floor((low + high) / 2);
    if ((blocks[middle]?.getBoundingClientRect().bottom ?? 0) > LEAD) high = middle;
    else low = middle + 1;
  }
  const scroller = doc.scrollingElement;
  const read = scroller
    ? Math.min(1, (scroller.scrollTop + scroller.clientHeight) / scroller.scrollHeight)
    : 0;
  return { block: Math.max(0, low), read };
}

/** Mounted once per document: the reader keys it by the file it shows. */
export function MobiView({ file, start, onPlace }: ReaderViewProps) {
  const { t } = useI18n();
  const settings = useSettings().reader;
  const frame = useRef<HTMLIFrameElement>(null);
  const area = useRef<HTMLDivElement>(null);
  const lastSaved = useRef(start);
  /** Set when the reader, not the person reading, scrolled the section, so that scroll is not saved. */
  const quietScroll = useRef(false);
  /** Set when the person reading moved and the place is not saved yet. */
  const unsaved = useRef(false);
  const [opened, setOpened] = useState<Opened>({ phase: "loading" });
  const [shown, setShown] = useState<{ target: Target; url: string } | null>(null);
  const [loaded, setLoaded] = useState<{ doc: Document; target: Target } | null>(null);
  const [progress, setProgress] = useState<number | null>(null);
  const [dialog, setDialog] = useState<"contents" | "settings" | null>(null);
  const ready = opened.phase === "ready" ? opened : null;

  const show = async (target: Target) => {
    const url = await ready?.book.sections[target.section]?.load?.();
    if (!url) return;
    if (url === shown?.url && loaded) scrollTo(loaded.doc, target.spot);
    else setShown({ target, url });
  };

  const turn = (step: 1 | -1) => {
    const scroller = loaded?.doc.scrollingElement;
    if (!scroller || !ready || !loaded) return;
    const atEdge =
      step === 1
        ? scroller.scrollTop + scroller.clientHeight >= scroller.scrollHeight - 2
        : scroller.scrollTop <= 0;
    if (!atEdge) {
      quietScroll.current = false;
      unsaved.current = true;
      scroller.scrollTop += step * (scroller.clientHeight - OVERLAP);
      return;
    }
    const section = ready.readable[ready.readable.indexOf(loaded.target.section) + step];
    if (section !== undefined)
      void show({ section, spot: { edge: step === 1 ? "start" : "end" }, moved: true });
  };
  const turns = { next: () => turn(1), previous: () => turn(-1) };
  usePageKeys(turns);

  const follow = async (href: string) => {
    try {
      const resolved = await ready?.book.resolveHref(href);
      if (resolved && ready?.readable.includes(resolved.index))
        await show({ section: resolved.index, spot: { anchor: resolved.anchor }, moved: true });
    } catch {
      // A link to somewhere the book does not have goes nowhere, as in other readers.
    }
  };

  const savedPlace = useEffectEvent(() => start);
  const measure = useEffectEvent((doc: Document, section: number): EbookPlace | null => {
    if (!ready) return null;
    const { block, read } = placeIn(doc);
    const ebookProgress = mobiProgress(ready.sizes, ready.readable.indexOf(section), read);
    setProgress(ebookProgress);
    return { ebookLocation: mobiLocation({ section, block }), ebookProgress };
  });
  const save = useEffectEvent((place: EbookPlace | null) => {
    if (!place || place.ebookLocation === lastSaved.current) return;
    lastSaved.current = place.ebookLocation;
    // Like the EPUB reader, a zero progress is left out so it never clears the server's.
    onPlace({
      ebookLocation: place.ebookLocation,
      ...(place.ebookProgress ? { ebookProgress: place.ebookProgress } : {}),
    });
  });
  const onFrameKey = useEffectEvent((event: KeyboardEvent) => {
    if (turnForKey(event, turns)) event.preventDefault();
  });
  const openLink = useEffectEvent((href: string | null) => {
    if (!href || !ready) return;
    if (!ready.book.isExternal(href)) void follow(href);
    else if (/^https?:/i.test(href)) window.open(href, "_blank", "noopener,noreferrer");
  });
  const onFrameClick = useEffectEvent((event: MouseEvent, view: Window & typeof globalThis) => {
    const link = event.target instanceof view.Element ? event.target.closest("a") : null;
    if (!link) return;
    event.preventDefault();
    openLink(link.getAttribute(LINK));
  });
  const keepPassageInView = useEffectEvent((settings: ReaderSettings) => {
    if (!loaded) return;
    const { block } = placeIn(loaded.doc);
    applyReaderCss(loaded.doc, mobiCss(settings));
    quietScroll.current = scrollTo(loaded.doc, { block });
  });

  // External system: foliate-js parses the MOBI or KF8 file into sections and a table of contents.
  useEffect(() => {
    let current = true;
    const opening = isMOBI(file).then((mobi) => {
      if (!mobi) throw new Error("Not a MOBI file");
      return new MOBI({ unzlib: unzlibSync }).open(file);
    });
    opening
      .then(async (book) => {
        if (!current) return;
        const readable = book.sections.flatMap((section, index) => (section.load ? [index] : []));
        const first = readable[0];
        if (first === undefined) throw new Error("No readable sections");
        const sizes = readable.map((index) => book.sections[index]?.size ?? 0);
        const saved = mobiPlace(savedPlace());
        const target: Target =
          saved && readable.includes(saved.section)
            ? { section: saved.section, spot: { block: saved.block }, moved: false }
            : { section: first, spot: { edge: "start" }, moved: false };
        const url = await book.sections[target.section]?.load?.();
        if (!current || !url) return;
        setOpened({ phase: "ready", book, readable, sizes, chapters: flattenToc(book.toc ?? []) });
        setShown({ target, url });
      })
      .catch(() => current && setOpened({ phase: "failed" }));
    return () => {
      current = false;
      void opening.then((book) => book.destroy()).catch(() => {});
    };
  }, [file]);

  // External system: the shown section's document, whose scrolling is watched and which reports keys and link
  // clicks. A layout effect, so leaving the reader can still measure the place before the frame is taken down.
  useLayoutEffect(() => {
    if (!loaded) return;
    const { doc, target } = loaded;
    const view = doc.defaultView;
    if (!view) return;
    const element = frame.current;
    /** Whether the frame still shows this section: one being replaced by the next reads as scrolled to its top. */
    const showing = () => element?.contentDocument === doc && element.src === withoutFragment(doc.URL);
    let latest = measure(doc, target.section);
    if (target.moved) save(latest);
    let timer: ReturnType<typeof setTimeout> | undefined;
    const flush = () => {
      clearTimeout(timer);
      unsaved.current = false;
      save(latest);
    };
    // WebKit sends no events from a document that may not run scripts, so its scrolling is watched from here.
    // Arriving at the target has already scrolled; only later scrolling counts.
    quietScroll.current = false;
    let scrolled = doc.scrollingElement?.scrollTop;
    // Nor does it report keys there, so a click in the text hands the keyboard back to the reader; a link reached with
    // Tab keeps it, and Enter follows it like a click.
    let heard = false;
    const hear = () => {
      heard = true;
    };
    doc.addEventListener("abs-probe", hear);
    doc.dispatchEvent(new view.Event("abs-probe"));
    doc.removeEventListener("abs-probe", hear);
    let frameRequest = requestAnimationFrame(function watch() {
      frameRequest = requestAnimationFrame(watch);
      if (element?.contentDocument !== doc) return;
      // A link followed in the book shows as its section's address taking the link's fragment.
      if (view.location.hash.startsWith(LINK_FRAGMENT)) {
        const hash = view.location.hash;
        view.history.replaceState(null, "", withoutFragment(doc.URL));
        const link = Array.from(doc.querySelectorAll(`[${LINK}]`)).find(
          (candidate) => (candidate.getAttribute("href") ?? candidate.getAttributeNS(XLINK, "href")) === hash,
        );
        openLink(link?.getAttribute(LINK) ?? null);
      }
      const inText = !doc.activeElement || doc.activeElement === doc.body;
      if (!heard && document.activeElement === element && inText)
        area.current?.focus({ preventScroll: true });
      if (!showing() || doc.scrollingElement?.scrollTop === scrolled) return;
      scrolled = doc.scrollingElement?.scrollTop;
      const quiet = quietScroll.current;
      quietScroll.current = false;
      if (!quiet) unsaved.current = true;
      latest = measure(doc, target.section);
      clearTimeout(timer);
      if (unsaved.current) timer = setTimeout(flush, 300);
    });
    const onKey = (event: KeyboardEvent) => onFrameKey(event);
    const onClick = (event: MouseEvent) => onFrameClick(event, view);
    doc.addEventListener("keydown", onKey);
    doc.addEventListener("click", onClick);
    return () => {
      doc.removeEventListener("keydown", onKey);
      doc.removeEventListener("click", onClick);
      cancelAnimationFrame(frameRequest);
      if (!unsaved.current) return;
      // A section replaced by the next has already left the frame; its last measured place stands.
      if (showing()) latest = measure(doc, target.section);
      flush();
    };
  }, [loaded]);

  // External system: the shown section's document takes the reader's display settings.
  useEffect(() => keepPassageInView(settings), [settings]);

  const onFrameLoad = () => {
    const doc = frame.current?.contentDocument;
    if (!doc?.body || !shown) return;
    applyReaderCss(doc, mobiCss(settings));
    routeLinks(doc);
    quietScroll.current = scrollTo(doc, shown.target.spot) && !shown.target.moved;
    setLoaded({ doc, target: shown.target });
  };

  const background = readerThemes[settings.theme].background;
  return (
    <>
      <div ref={area} tabIndex={-1} className="relative min-h-0 flex-1 outline-none" style={{ background }}>
        {shown ? (
          <iframe
            ref={frame}
            src={shown.url}
            // Same origin so the reader can style and follow the book; no scripts, so the book cannot act as this app.
            sandbox="allow-same-origin"
            title={t("WebBookText")}
            onLoad={onFrameLoad}
            className="absolute inset-0 size-full border-0"
            style={{ background }}
          />
        ) : null}
        {opened.phase === "failed" ? (
          <div className="absolute inset-0 bg-bg">
            <Alert>{t("WebDocumentUnreadable")}</Alert>
          </div>
        ) : !loaded ? (
          <div className="absolute inset-0 bg-bg">
            <Spinner label={t("MessageLoading")} />
          </div>
        ) : null}
      </div>
      {ready ? (
        <ReaderBar onPrevious={turns.previous} onNext={turns.next}>
          <BookControls
            status={progress === null ? null : `${Math.round(progress * 100)}%`}
            onContents={() => setDialog("contents")}
            onSettings={() => setDialog("settings")}
          />
        </ReaderBar>
      ) : null}
      {dialog === "contents" && ready ? (
        <ContentsDialog
          chapters={ready.chapters}
          onPick={(chapter) => void follow(chapter.href)}
          onClose={() => setDialog(null)}
        />
      ) : null}
      {dialog === "settings" ? <ReaderSettingsDialog paged={false} onClose={() => setDialog(null)} /> : null}
    </>
  );
}
