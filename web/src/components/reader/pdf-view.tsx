"use client";

import "pdfjs-dist/web/pdf_viewer.css";
import { RotateCw } from "lucide-react";
import type { PDFDocumentProxy, PDFPageProxy } from "pdfjs-dist";
import * as pdfjs from "pdfjs-dist";
import { useEffect, useRef, useState } from "react";
import { z } from "zod";
import { Button } from "@/components/ui/button";
import { Alert, Spinner } from "@/components/ui/status";
import { useI18n } from "@/i18n/i18n";
import { pageFromLocation, pageProgress } from "@/lib/abs/ebooks";
import { readStored, writeStored } from "@/lib/storage/local";
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

export function PdfView({ file, start, onPlace, cacheKey }: ReaderViewProps) {
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
  return <PdfPages doc={loaded.doc} start={start} onPlace={onPlace} cacheKey={cacheKey} />;
}

const rotationSchema = z.number().int().min(0).max(270).multipleOf(90);

function PdfPages({
  doc,
  start,
  onPlace,
  cacheKey,
}: {
  doc: PDFDocumentProxy;
  start: string | null;
  onPlace: ReaderViewProps["onPlace"];
  cacheKey: ReaderViewProps["cacheKey"];
}) {
  const { t } = useI18n();
  const rotationKey = `abs:pdf-rotation:${cacheKey}`;
  const [rotation, setRotation] = useState(() => {
    try {
      return readStored(rotationKey, rotationSchema) ?? 0;
    } catch {
      return 0;
    }
  });
  const rotate = () => {
    const next = (rotation + 90) % 360;
    setRotation(next);
    try {
      writeStored(rotationKey, next);
    } catch {
      // Storage can be refused; rotating still works for this opening.
    }
  };
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
        <PdfPage doc={doc} number={page} rotation={rotation} onLink={go} />
      </div>
      <div className="flex justify-center border-t border-line">
        <Button variant="ghost" size="sm" onClick={rotate} aria-label={t("WebRotatePage")}>
          <RotateCw aria-hidden className="size-4" />
          {t("WebRotatePage")}
        </Button>
      </div>
      <PageControls page={page} pages={pages} onGo={go} />
    </>
  );
}

function PdfPage({
  doc,
  number,
  rotation,
  onLink,
}: {
  doc: PDFDocumentProxy;
  number: number;
  rotation: number;
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
        const angle = (pdfPage.rotate + rotation) % 360;
        const base = pdfPage.getViewport({ scale: 1, rotation: angle });
        const viewport = pdfPage.getViewport({ scale: width / base.width, rotation: angle });
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
        textLayer.style.setProperty("--scale-round-x", "1px");
        textLayer.style.setProperty("--scale-round-y", "1px");
        layer = new pdfjs.TextLayer({
          textContentSource: pdfPage.streamTextContent(),
          container: textLayer,
          viewport,
        });
        const found = await pageLinks(doc, pdfPage, viewport);
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
  }, [doc, number, width, rotation]);

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
async function pageLinks(
  doc: PDFDocumentProxy,
  page: PDFPageProxy,
  viewport: ReturnType<PDFPageProxy["getViewport"]>,
): Promise<PageLink[]> {
  const [annotations, content] = await Promise.all([page.getAnnotations(), page.getTextContent()]);
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
    const [left, top] = viewport.convertToViewportPoint(x1, y1);
    const [right, bottom] = viewport.convertToViewportPoint(x2, y2);
    const box = {
      left: (Math.min(left, right) / viewport.width) * 100,
      top: (Math.min(top, bottom) / viewport.height) * 100,
      width: (Math.abs(right - left) / viewport.width) * 100,
      height: (Math.abs(bottom - top) / viewport.height) * 100,
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
