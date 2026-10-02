"use client";

import { Archive } from "libarchive.js";
import { Info, LayoutGrid } from "lucide-react";
import { useEffect, useState } from "react";
import { z } from "zod";
import { Button } from "@/components/ui/button";
import { Dialog } from "@/components/ui/dialog";
import { Alert, Spinner } from "@/components/ui/status";
import { useI18n } from "@/i18n/i18n";
import { comicPages, pageImageType, pageName } from "@/lib/abs/comics";
import { pageFromLocation, pageProgress } from "@/lib/abs/ebooks";
import { ContentsDialog } from "./contents";
import { PageControls, usePageKeys, useSwipe } from "./paging";
import type { ReaderViewProps } from "./reader";

type ComicArchive = Awaited<ReturnType<typeof Archive.open>>;

type Opened =
  | { phase: "loading" }
  | { phase: "failed" }
  | { phase: "ready"; archive: ComicArchive; pages: string[]; info: [string, string][] };

/** libarchive lists each file under its folder path; entries without a name are folders. */
const archiveEntry = z.object({ path: z.string(), file: z.object({ name: z.string() }) });

async function archivePaths(archive: ComicArchive) {
  const entries: unknown[] = await archive.getFilesArray();
  return entries.flatMap((entry) => {
    const parsed = archiveEntry.safeParse(entry);
    return parsed.success ? [parsed.data.path + parsed.data.file.name] : [];
  });
}

/** ComicInfo.xml fields with a plain value, in the file's order. */
async function comicInfo(archive: ComicArchive, paths: string[]): Promise<[string, string][]> {
  const path = paths.find((entry) => /(^|\/)comicinfo\.xml$/i.test(entry));
  if (!path) return [];
  const text = await (await archive.extractSingleFile(path)).text();
  const xml = new DOMParser().parseFromString(text, "text/xml");
  if (xml.querySelector("parsererror")) return [];
  return [...xml.documentElement.children].flatMap((field) => {
    const value = field.textContent?.trim();
    return field.children.length === 0 && value ? [[field.tagName, value] satisfies [string, string]] : [];
  });
}

export function ComicView({ file, start, onPlace }: ReaderViewProps) {
  const { t } = useI18n();
  const [opened, setOpened] = useState<Opened>({ phase: "loading" });

  // External system: libarchive unpacks the archive in its worker, which is stopped when the comic closes.
  useEffect(() => {
    let current = true;
    Archive.init({ workerUrl: `${process.env.NEXT_PUBLIC_BASE_PATH ?? ""}/libarchive/worker-bundle.js` });
    const opening = Archive.open(new File([file], "comic"));
    opening
      .then(async (archive) => {
        const paths = await archivePaths(archive);
        const pages = comicPages(paths);
        const info = await comicInfo(archive, paths).catch(() => []);
        if (!current) return;
        setOpened(pages.length ? { phase: "ready", archive, pages, info } : { phase: "failed" });
      })
      .catch(() => current && setOpened({ phase: "failed" }));
    return () => {
      current = false;
      void opening.then((archive) => archive.close()).catch(() => undefined);
    };
  }, [file]);

  if (opened.phase === "loading") return <Spinner label={t("MessageLoading")} />;
  if (opened.phase === "failed") return <Alert>{t("WebDocumentUnreadable")}</Alert>;
  return (
    <ComicPages
      archive={opened.archive}
      pages={opened.pages}
      info={opened.info}
      start={start}
      onPlace={onPlace}
    />
  );
}

function ComicPages({
  archive,
  pages,
  info,
  start,
  onPlace,
}: {
  archive: ComicArchive;
  pages: string[];
  info: [string, string][];
  start: string | null;
  onPlace: ReaderViewProps["onPlace"];
}) {
  const { t } = useI18n();
  const [chosen, setChosen] = useState<number | null>(null);
  const [dialog, setDialog] = useState<"pages" | "info" | null>(null);
  const page = chosen ?? pageFromLocation(start, pages.length);
  const path = pages[page - 1];

  const go = (next: number) => {
    const target = Math.min(pages.length, Math.max(1, next));
    if (target === page) return;
    setChosen(target);
    onPlace(pageProgress(target, pages.length));
  };
  const turns = { next: () => go(page + 1), previous: () => go(page - 1) };
  usePageKeys(turns);
  const swipe = useSwipe(turns);

  return (
    <>
      <div className="relative min-h-0 flex-1 bg-surface-2" {...swipe}>
        {path ? <ComicImage key={path} archive={archive} path={path} page={page} /> : null}
      </div>
      <PageControls page={page} pages={pages.length} onGo={go}>
        <Button
          variant="ghost"
          size="icon"
          aria-label={t("WebComicPages")}
          onClick={() => setDialog("pages")}
        >
          <LayoutGrid aria-hidden className="size-5" />
        </Button>
        {info.length ? (
          <Button
            variant="ghost"
            size="icon"
            aria-label={t("WebComicInfo")}
            onClick={() => setDialog("info")}
          >
            <Info aria-hidden className="size-5" />
          </Button>
        ) : null}
      </PageControls>

      {dialog === "pages" ? (
        <ContentsDialog
          title={t("WebComicPages")}
          chapters={pages.map((entry, index) => ({
            key: entry,
            label: pageName(entry),
            href: String(index + 1),
            depth: 0,
          }))}
          current={path}
          onPick={(chapter) => go(Number(chapter.href))}
          onClose={() => setDialog(null)}
        />
      ) : null}
      <Dialog open={dialog === "info"} onClose={() => setDialog(null)} title={t("WebComicInfo")}>
        <dl className="grid max-h-[60vh] grid-cols-[auto_1fr] gap-x-4 gap-y-1 overflow-y-auto text-sm">
          {info.map(([name, value]) => (
            <div key={name} className="contents">
              <dt className="font-medium text-muted">{name}</dt>
              <dd className="break-words">{value}</dd>
            </div>
          ))}
        </dl>
        <div className="flex justify-end">
          <Button variant="ghost" onClick={() => setDialog(null)}>
            {t("WebClose")}
          </Button>
        </div>
      </Dialog>
    </>
  );
}

type Extracted = { phase: "loading" } | { phase: "failed" } | { phase: "ready"; url: string };

/** Mounted once per page: the reader keys it by the page's path. */
function ComicImage({ archive, path, page }: { archive: ComicArchive; path: string; page: number }) {
  const { t } = useI18n();
  const [extracted, setExtracted] = useState<Extracted>({ phase: "loading" });

  // External system: the archive's worker unpacks the page, shown from an object URL that lives as long as the page.
  useEffect(() => {
    let current = true;
    let url: string | null = null;
    archive
      .extractSingleFile(path)
      .then((image) => {
        if (!current) return;
        url = URL.createObjectURL(new Blob([image], { type: pageImageType(path) ?? image.type }));
        setExtracted({ phase: "ready", url });
      })
      .catch(() => current && setExtracted({ phase: "failed" }));
    return () => {
      current = false;
      if (url) URL.revokeObjectURL(url);
    };
  }, [archive, path]);

  if (extracted.phase === "loading") return <Spinner label={t("MessageLoading")} />;
  if (extracted.phase === "failed") return <Alert>{t("WebDocumentUnreadable")}</Alert>;
  return (
    <img
      src={extracted.url}
      alt={t("WebPage", page)}
      className="absolute inset-0 m-auto max-h-full max-w-full object-contain p-2"
    />
  );
}
