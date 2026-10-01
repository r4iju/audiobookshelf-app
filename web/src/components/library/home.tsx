"use client";

import { ChevronRight } from "lucide-react";
import Link from "next/link";
import { errorMessage } from "@/components/app/errors";
import { shelfWidths } from "@/components/media/item-card";
import { Button } from "@/components/ui/button";
import { Alert, EmptyState, Spinner } from "@/components/ui/status";
import { isStringKey, useI18n } from "@/i18n/i18n";
import type { CoverShape } from "@/lib/abs/media";
import { usePersonalized } from "@/lib/abs/queries";
import type { Shelf } from "@/lib/abs/schemas";
import { AuthorCard, ItemCard, SeriesCard } from "./cards";
import { useLibrary } from "./use-library";

export function LibraryHome({ libraryId }: { libraryId: string }) {
  const { t } = useI18n();
  const { library, shape } = useLibrary(libraryId);
  const shelves = usePersonalized(libraryId);

  return (
    <div className="flex flex-col gap-8">
      <header className="flex items-end justify-between gap-4">
        <h1 className="text-2xl font-bold tracking-tight lg:text-3xl">{library?.name ?? t("WebHome")}</h1>
        <Link
          href={`/library/${libraryId}/items`}
          className="inline-flex items-center gap-1 rounded-lg text-sm font-medium text-accent focus-ring"
        >
          {t("ButtonLibrary")}
          <ChevronRight aria-hidden className="size-4 rtl:rotate-180" />
        </Link>
      </header>
      {shelves.isPending ? (
        <Spinner label={t("WebLoading")} />
      ) : shelves.isError ? (
        <Alert
          action={
            <Button size="sm" onClick={() => shelves.refetch()}>
              {t("WebRetry")}
            </Button>
          }
        >
          {errorMessage(t, shelves.error)}
        </Alert>
      ) : shelves.data.length === 0 ? (
        <EmptyState title={t("MessageNoItems")} />
      ) : (
        shelves.data.map((shelf) => (
          <ShelfRow key={shelf.id} shelf={shelf} libraryId={libraryId} shape={shape} />
        ))
      )}
    </div>
  );
}

function ShelfRow({ shelf, libraryId, shape }: { shelf: Shelf; libraryId: string; shape: CoverShape }) {
  const { t } = useI18n();
  const headingId = `shelf-${shelf.id}`;
  const label = isStringKey(shelf.labelStringKey) ? t(shelf.labelStringKey) : shelf.label;
  const width = shelf.type === "authors" ? shelfWidths.square : shelfWidths[shape];
  return (
    <section aria-labelledby={headingId} className="flex flex-col gap-3">
      <h2 id={headingId} className="text-lg font-semibold">
        {label}
      </h2>
      <ul className="-mx-4 flex snap-x gap-4 overflow-x-auto px-4 pb-2 lg:-mx-8 lg:px-8">
        {shelf.type === "series"
          ? shelf.entities.map((series) => (
              <li key={series.id} className={`shrink-0 snap-start ${width}`}>
                <SeriesCard series={series} libraryId={libraryId} shape={shape} />
              </li>
            ))
          : shelf.type === "authors"
            ? shelf.entities.map((author) => (
                <li key={author.id} className={`shrink-0 snap-start ${width}`}>
                  <AuthorCard author={author} libraryId={libraryId} />
                </li>
              ))
            : shelf.entities.map((item) => (
                <li
                  key={`${item.id}-${item.recentEpisode?.id ?? ""}`}
                  className={`shrink-0 snap-start ${width}`}
                >
                  <ItemCard item={item} shape={shape} />
                </li>
              ))}
      </ul>
    </section>
  );
}
