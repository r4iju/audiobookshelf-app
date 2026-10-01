"use client";

import { ArrowLeft } from "lucide-react";
import dynamic from "next/dynamic";
import { errorMessage } from "@/components/app/errors";
import { InlineError } from "@/components/app/inline-error";
import { ButtonLink } from "@/components/ui/button";
import { QueryState } from "@/components/ui/query-state";
import { Alert, Spinner } from "@/components/ui/status";
import { useI18n } from "@/i18n/i18n";
import { type EbookKind, type ReadableEbook, readableEbook } from "@/lib/abs/ebooks";
import { type EbookPlace, useSaveEbookPlace } from "@/lib/abs/mutations";
import { useEbookFile, useItem, useServerItemProgress } from "@/lib/abs/queries";
import type { LibraryItem } from "@/lib/abs/schemas";

export interface ReaderViewProps {
  file: Blob;
  /** The saved location to open at, in the format's own notation. */
  start: string | null;
  onPlace: (place: EbookPlace) => void;
  /** Names the document for what this browser keeps about it, such as an EPUB's generated locations. */
  cacheKey: string;
}

// The document engines touch browser-only APIs as they load, so they are only ever loaded in the browser.
const views: Record<EbookKind, React.ComponentType<ReaderViewProps> | null> = {
  pdf: dynamic(() => import("./pdf-view").then((module) => module.PdfView), { ssr: false }),
  epub: dynamic(() => import("./epub-view").then((module) => module.EpubView), { ssr: false }),
  mobi: null,
  comic: null,
};

export function Reader({ itemId, fileIno }: { itemId: string; fileIno: string | null }) {
  const { t } = useI18n();
  const item = useItem(itemId);
  const ebook = item.data ? readableEbook(item.data, fileIno) : null;
  const View = ebook ? views[ebook.kind] : null;
  return (
    <div className="flex h-full flex-col">
      <header className="flex items-center gap-2 border-b border-line px-2 py-2 sm:px-4">
        <ButtonLink href={`/item/${itemId}`} variant="ghost" size="icon" aria-label={t("ButtonBack")}>
          <ArrowLeft aria-hidden className="size-5" />
        </ButtonLink>
        {item.data ? (
          <h1 className="min-w-0 flex-1 truncate font-semibold">{item.data.media.metadata.title}</h1>
        ) : null}
      </header>
      <div className="flex min-h-0 flex-1 flex-col">
        <QueryState query={item}>
          {(data) =>
            ebook && View ? (
              <ReaderBody item={data} ebook={ebook} View={View} />
            ) : (
              <Alert>{t("WebReaderUnsupported")}</Alert>
            )
          }
        </QueryState>
      </div>
    </div>
  );
}

function ReaderBody({
  item,
  ebook,
  View,
}: {
  item: LibraryItem;
  ebook: ReadableEbook;
  View: React.ComponentType<ReaderViewProps>;
}) {
  const { t } = useI18n();
  const file = useEbookFile(ebook.path);
  const progress = useServerItemProgress(item.id);
  const save = useSaveEbookPlace(item.id);

  // The place is read fresh on every opening, so a book follows wherever another device left it.
  if (file.isPending || (ebook.keepsProgress && !progress.isFetchedAfterMount))
    return <Spinner label={t("WebLoading")} />;
  if (file.isError) return <Alert>{errorMessage(t, file.error)}</Alert>;
  return (
    <>
      <InlineError error={progress.error ?? save.error} />
      <View
        key={ebook.path}
        file={file.data}
        cacheKey={ebook.path}
        start={ebook.keepsProgress ? (progress.data?.ebookLocation ?? null) : null}
        onPlace={(place) => {
          if (ebook.keepsProgress) save.mutate(place);
        }}
      />
    </>
  );
}
