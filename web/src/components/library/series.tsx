"use client";

import { usePathname } from "next/navigation";
import { CardGrid } from "@/components/media/item-card";
import { QueryState } from "@/components/ui/query-state";
import { EmptyState } from "@/components/ui/status";
import { useI18n } from "@/i18n/i18n";
import { encodeFilter } from "@/lib/abs/browse";
import { PAGE_SIZE, useItems, useSeries, useSeriesList } from "@/lib/abs/queries";
import { ItemCard, SeriesCard } from "./cards";
import { Pager } from "./pager";
import { useLibrary } from "./use-library";

export function SeriesList({ libraryId, page }: { libraryId: string; page: number }) {
  const { t } = useI18n();
  const pathname = usePathname();
  const { shape } = useLibrary(libraryId);
  const series = useSeriesList(libraryId, page);
  const pages = Math.max(1, Math.ceil((series.data?.total ?? 0) / PAGE_SIZE));
  return (
    <div className="flex flex-col gap-6">
      <h1 className="text-2xl font-bold tracking-tight lg:text-3xl">{t("LabelSeries")}</h1>
      <QueryState query={series}>
        {(data) =>
          data.results.length === 0 ? (
            <EmptyState title={t("MessageNoSeries")} />
          ) : (
            <CardGrid shape={shape} label={t("LabelSeries")}>
              {data.results.map((entry) => (
                <li key={entry.id}>
                  <SeriesCard series={entry} libraryId={libraryId} shape={shape} />
                </li>
              ))}
            </CardGrid>
          )
        }
      </QueryState>
      <Pager
        page={page}
        pages={pages}
        hrefFor={(next) => (next > 1 ? `${pathname}?page=${next}` : pathname)}
        labels={{
          nav: t("WebPagination"),
          previous: t("WebPrevious"),
          next: t("WebNext"),
          pageOf: t("WebPageOf", page, pages),
        }}
      />
    </div>
  );
}

export function SeriesDetail({ libraryId, seriesId }: { libraryId: string; seriesId: string }) {
  const { t } = useI18n();
  const { shape } = useLibrary(libraryId);
  const series = useSeries(libraryId, seriesId);
  // The server orders a series filter by sequence when asked for the "sequence" sort.
  const books = useItems(
    libraryId,
    { sort: "sequence", desc: false, filter: encodeFilter("series", seriesId), page: 1 },
    false,
  );
  return (
    <div className="flex flex-col gap-6">
      <QueryState query={series}>
        {(data) => (
          <header>
            <p className="text-sm font-medium text-muted">{t("LabelSeries")}</p>
            <h1 className="text-2xl font-bold tracking-tight lg:text-3xl">{data.name}</h1>
          </header>
        )}
      </QueryState>
      <QueryState query={books}>
        {(data) => (
          <CardGrid shape={shape} label={t("WebLibraryItems")}>
            {data.results.map((item) => (
              <li key={item.id}>
                <ItemCard item={item} shape={shape} />
              </li>
            ))}
          </CardGrid>
        )}
      </QueryState>
    </div>
  );
}
