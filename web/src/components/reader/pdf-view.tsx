"use client";

import "pdfjs-dist/web/pdf_viewer.css";
import type { PDFDocumentProxy, PDFPageProxy } from "pdfjs-dist";
import * as pdfjs from "pdfjs-dist";
import { useEffect, useRef, useState } from "react";
import { Alert, Spinner } from "@/components/ui/status";
import { useI18n } from "@/i18n/i18n";
import { pageFromLocation, pageProgress } from "@/lib/abs/ebooks";
import { PageControls, usePageKeys, useSwipe } from "./paging";
import type { ReaderViewProps } from "./reader";

pdfjs.GlobalWorkerOptions.workerSrc = new URL(
  "pdfjs-dist/build/pdf.worker.min.mjs",
  import.meta.url,
).toString();

type Loaded = { phase: "loading" } | { phase: "failed" } | { phase: "ready"; doc: PDFDocumentProxy };

interface PageLink {
  key: string;
  /** Percentages of the page box, so links follow the page as it scales. */
  box: { left: number; top: number; width: number; height: number };
  label: string;
  target: { page: number } | { url: string };
}

export function PdfView({ file, start, onPlace }: ReaderViewProps) {
  const { t } = useI18n();
  const [loaded, setLoaded] = useState<Loaded>({ phase: "loading" });

  // External system: pdf.js parses the document in its worker.
  useEffect(() => {
    let task: pdfjs.PDFDocumentLoadingTask | null = null;
    let current = true;
    file
      .arrayBuffer()
      .then((data) => {
        if (!current) return;
        task = pdfjs.getDocument({ data: new Uint8Array(data) });
        return task.promise.then((doc) => current && setLoaded({ phase: "ready", doc }));
      })
      .catch(() => current && setLoaded({ phase: "failed" }));
    return () => {
      current = false;
      void task?.destroy();
    };
  }, [file]);

  if (loaded.phase === "loading") return <Spinner label={t("MessageLoading")} />;
  if (loaded.phase === "failed") return <Alert>{t("WebDocumentUnreadable")}</Alert>;
  return <PdfPages doc={loaded.doc} start={start} onPlace={onPlace} />;
}

function PdfPages({
  doc,
  start,
  onPlace,
}: {
  doc: PDFDocumentProxy;
  start: string | null;
  onPlace: ReaderViewProps["onPlace"];
}) {
  const pages = doc.numPages;
  const [chosen, setChosen] = useState<number | null>(null);
  const page = chosen ?? pageFromLocation(start, pages);

  const go = (next: number) => {
    const target = Math.min(pages, Math.max(1, next));
    if (target === page) return;
    setChosen(target);
    onPlace(pageProgress(target, pages));
  };
  usePageKeys({ next: () => go(page + 1), previous: () => go(page - 1) });
  const swipe = useSwipe({ next: () => go(page + 1), previous: () => go(page - 1) });

  return (
    <>
      <div className="min-h-0 flex-1 overflow-auto bg-surface-2" {...swipe}>
        <PdfPage doc={doc} number={page} onLink={go} />
      </div>
      <PageControls page={page} pages={pages} onGo={go} />
    </>
  );
}

function PdfPage({
  doc,
  number,
  onLink,
}: {
  doc: PDFDocumentProxy;
  number: number;
  onLink: (page: number) => void;
}) {
  const { t } = useI18n();
  const frame = useRef<HTMLDivElement>(null);
  const canvas = useRef<HTMLCanvasElement>(null);
  const text = useRef<HTMLDivElement>(null);
  const [width, setWidth] = useState(0);
  const [links, setLinks] = useState<PageLink[]>([]);
  const [ratio, setRatio] = useState(1.294);

  // External system: the page is drawn to fit the space the window gives it.
  useEffect(() => {
    const element = frame.current;
    if (!element) return;
    const observer = new ResizeObserver(
      ([entry]) => entry && setWidth(Math.min(960, Math.floor(entry.contentRect.width))),
    );
    observer.observe(element);
    return () => observer.disconnect();
  }, []);

  // External system: pdf.js draws the page, lays out its selectable text and reports its links.
  useEffect(() => {
    if (!width || !canvas.current || !text.current) return;
    const target = canvas.current;
    const textLayer = text.current;
    let current = true;
    let render: pdfjs.RenderTask | null = null;
    let layer: pdfjs.TextLayer | null = null;
    doc
      .getPage(number)
      .then(async (pdfPage) => {
        if (!current) return;
        const base = pdfPage.getViewport({ scale: 1 });
        const viewport = pdfPage.getViewport({ scale: width / base.width });
        setRatio(base.height / base.width);
        const outputScale = window.devicePixelRatio || 1;
        target.width = Math.floor(viewport.width * outputScale);
        target.height = Math.floor(viewport.height * outputScale);
        render = pdfPage.render({
          canvas: target,
          viewport,
          transform: outputScale === 1 ? undefined : [outputScale, 0, 0, outputScale, 0, 0],
        });
        textLayer.replaceChildren();
        textLayer.style.setProperty("--total-scale-factor", String(viewport.scale));
        layer = new pdfjs.TextLayer({
          textContentSource: pdfPage.streamTextContent(),
          container: textLayer,
          viewport,
        });
        const found = await pageLinks(doc, pdfPage);
        await Promise.all([render.promise, layer.render()]);
        if (current) setLinks(found);
      })
      .catch((error: unknown) => {
        if (!(error instanceof pdfjs.RenderingCancelledException) && current) setLinks([]);
      });
    return () => {
      current = false;
      render?.cancel();
      layer?.cancel();
    };
  }, [doc, number, width]);

  return (
    <div ref={frame} className="mx-auto w-full max-w-[960px] px-2 py-4 sm:px-4">
      <div
        className="relative mx-auto overflow-hidden bg-white shadow-lg"
        style={{ width: width || undefined, aspectRatio: `1 / ${ratio}` }}
      >
        <canvas ref={canvas} aria-hidden className="absolute inset-0 size-full" />
        <div ref={text} className="textLayer" />
        {links.map((link) => {
          const style = {
            left: `${link.box.left}%`,
            top: `${link.box.top}%`,
            width: `${link.box.width}%`,
            height: `${link.box.height}%`,
          };
          const className = "absolute z-10 rounded-sm focus-ring hover:bg-accent/15";
          return "url" in link.target ? (
            <a
              key={link.key}
              href={link.target.url}
              target="_blank"
              rel="noreferrer"
              className={className}
              style={style}
            >
              <span className="sr-only">{link.label}</span>
            </a>
          ) : (
            <a
              key={link.key}
              href={`#page-${link.target.page}`}
              className={className}
              style={style}
              onClick={(event) => {
                event.preventDefault();
                if ("page" in link.target) onLink(link.target.page);
              }}
            >
              <span className="sr-only">{link.label || t("WebGoToPageNumber", link.target.page)}</span>
            </a>
          );
        })}
      </div>
    </div>
  );
}

/** Link annotations with the words printed under them as their accessible names. */
async function pageLinks(doc: PDFDocumentProxy, page: PDFPageProxy): Promise<PageLink[]> {
  const [annotations, content] = await Promise.all([page.getAnnotations(), page.getTextContent()]);
  const [left = 0, bottom = 0, right = 0, top = 0] = page.view;
  const [pageWidth, pageHeight] = [right - left, top - bottom];
  const links: PageLink[] = [];
  for (const annotation of annotations) {
    if (annotation.subtype !== "Link") continue;
    const [x1 = 0, y1 = 0, x2 = 0, y2 = 0] = annotation.rect as number[];
    const label = content.items
      .flatMap((item) => {
        if (!("str" in item)) return [];
        const [x, y] = [item.transform[4], item.transform[5]];
        return x >= x1 - 2 && x <= x2 && y >= y1 - 2 && y <= y2 ? [item.str] : [];
      })
      .join(" ")
      .trim();
    const box = {
      left: ((Math.min(x1, x2) - left) / pageWidth) * 100,
      top: ((top - Math.max(y1, y2)) / pageHeight) * 100,
      width: (Math.abs(x2 - x1) / pageWidth) * 100,
      height: (Math.abs(y2 - y1) / pageHeight) * 100,
    };
    if (typeof annotation.url === "string") {
      links.push({
        key: annotation.id,
        box,
        label: label || annotation.url,
        target: { url: annotation.url },
      });
      continue;
    }
    const target = await destinationPage(doc, annotation.dest);
    if (target) links.push({ key: annotation.id, box, label, target: { page: target } });
  }
  return links;
}

async function destinationPage(doc: PDFDocumentProxy, dest: unknown) {
  try {
    const explicit = typeof dest === "string" ? await doc.getDestination(dest) : dest;
    if (!Array.isArray(explicit)) return null;
    const [ref] = explicit;
    if (typeof ref === "number") return ref + 1;
    return (await doc.getPageIndex(ref)) + 1;
  } catch {
    return null;
  }
}
