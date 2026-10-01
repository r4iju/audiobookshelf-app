"use client";

import { ArrowDownWideNarrow, ArrowUpNarrowWide } from "lucide-react";
import { usePathname, useRouter } from "next/navigation";
import { errorMessage } from "@/components/app/errors";
import { CardGrid } from "@/components/media/item-card";
import { Button } from "@/components/ui/button";
import { SelectField } from "@/components/ui/field";
import { Alert, EmptyState, Spinner } from "@/components/ui/status";
import { type Translate, useI18n } from "@/i18n/i18n";
import { type BrowseState, browseToParams, encodeFilter, naturalDesc, sortsFor } from "@/lib/abs/browse";
import { PAGE_SIZE, useFilterData, useItems } from "@/lib/abs/queries";
import type { FilterData, Library } from "@/lib/abs/schemas";
import { useSettings } from "@/lib/settings/store";
import { ItemCard } from "./cards";
import { Pager } from "./pager";
import { useLibrary } from "./use-library";

type FilterGroup = { label: string; options: Array<{ value: string; label: string }> };

function filterGroups(
  t: Translate,
  mediaType: Library["mediaType"],
  data: FilterData | null | undefined,
): FilterGroup[] {
  const named = (group: string, values: Array<{ id: string; name: string }>) =>
    values.map((entry) => ({ value: encodeFilter(group, entry.id), label: entry.name }));
  const plain = (group: string, values: string[]) =>
    values.map((value) => ({ value: encodeFilter(group, value), label: value }));
  const groups: FilterGroup[] =
    mediaType === "book"
      ? [
          {
            label: t("LabelProgress"),
            options: [
              { value: encodeFilter("progress", "finished"), label: t("LabelFinished") },
              { value: encodeFilter("progress", "in-progress"), label: t("LabelInProgress") },
              { value: encodeFilter("progress", "not-started"), label: t("LabelNotStarted") },
              { value: encodeFilter("progress", "not-finished"), label: t("LabelNotFinished") },
            ],
          },
          {
            label: t("LabelEbooks"),
            options: [
              { value: encodeFilter("ebooks", "ebook"), label: t("LabelHasEbook") },
              { value: encodeFilter("ebooks", "supplementary"), label: t("LabelHasSupplementaryEbook") },
            ],
          },
          { label: t("LabelSeries"), options: named("series", data?.series ?? []) },
          { label: t("LabelAuthors"), options: named("authors", data?.authors ?? []) },
          { label: t("LabelNarrators"), options: plain("narrators", data?.narrators ?? []) },
        ]
      : [];
  groups.push(
    { label: t("LabelGenres"), options: plain("genres", data?.genres ?? []) },
    { label: t("LabelTags"), options: plain("tags", data?.tags ?? []) },
    { label: t("LabelLanguage"), options: plain("languages", data?.languages ?? []) },
  );
  return groups.filter((group) => group.options.length > 0);
}

export function LibraryBrowse({ libraryId, state }: { libraryId: string; state: BrowseState }) {
  const { t, locale } = useI18n();
  const router = useRouter();
  const pathname = usePathname();
  const settings = useSettings();
  const { library, shape } = useLibrary(libraryId);
  const mediaType = library?.mediaType ?? "book";
  const items = useItems(libraryId, state, mediaType === "book" && settings.collapseSeries);
  const filterData = useFilterData(libraryId);

  const hrefFor = (next: BrowseState) => {
    const query = browseToParams(next);
    return query ? `${pathname}?${query}` : pathname;
  };
  const go = (change: Partial<BrowseState>) => router.push(hrefFor({ ...state, page: 1, ...change }));
  const total = items.data?.total ?? 0;
  const pages = Math.max(1, Math.ceil(total / PAGE_SIZE));
  const groups = filterGroups(t, mediaType, filterData.data?.filterdata);

  return (
    <div className="flex flex-col gap-6">
      <header className="flex flex-wrap items-end justify-between gap-4">
        <div>
          <h1 className="text-2xl font-bold tracking-tight lg:text-3xl">
            {library?.name ?? t("ButtonLibrary")}
          </h1>
          {items.data ? (
            <p className="text-sm text-muted">{t("WebItemsCount", total.toLocaleString(locale))}</p>
          ) : null}
        </div>
        <div className="flex flex-wrap items-end gap-3">
          <SelectField
            label={t("WebSortBy")}
            value={state.sort}
            onChange={(event) => go({ sort: event.target.value, desc: naturalDesc(event.target.value) })}
          >
            {sortsFor(mediaType).map(([value, label]) => (
              <option key={value} value={value}>
                {t(label)}
              </option>
            ))}
          </SelectField>
          <fieldset className="flex rounded-xl bg-surface-2 p-1">
            <legend className="sr-only">{t("WebSortDirection")}</legend>
            <Button
              size="sm"
              variant={state.desc ? "ghost" : "secondary"}
              aria-pressed={!state.desc}
              onClick={() => go({ desc: false })}
            >
              <ArrowUpNarrowWide aria-hidden className="size-4" />
              {t("WebAscending")}
            </Button>
            <Button
              size="sm"
              variant={state.desc ? "secondary" : "ghost"}
              aria-pressed={state.desc}
              onClick={() => go({ desc: true })}
            >
              <ArrowDownWideNarrow aria-hidden className="size-4" />
              {t("WebDescending")}
            </Button>
          </fieldset>
          <SelectField
            label={t("WebFilterBy")}
            value={state.filter ?? ""}
            onChange={(event) => go({ filter: event.target.value || null })}
            className="max-w-64"
          >
            <option value="">{t("LabelAll")}</option>
            {groups.map((group) => (
              <optgroup key={group.label} label={group.label}>
                {group.options.map((option) => (
                  <option key={option.value} value={option.value}>
                    {option.label}
                  </option>
                ))}
              </optgroup>
            ))}
          </SelectField>
        </div>
      </header>

      {items.isPending ? (
        <Spinner label={t("WebLoading")} />
      ) : items.isError ? (
        <Alert
          action={
            <Button size="sm" onClick={() => items.refetch()}>
              {t("WebRetry")}
            </Button>
          }
        >
          {errorMessage(t, items.error)}
        </Alert>
      ) : items.data.results.length === 0 ? (
        <EmptyState title={t("MessageNoItemsFound")} />
      ) : (
        <div
          aria-busy={items.isPlaceholderData}
          className={items.isPlaceholderData ? "opacity-60 transition-opacity" : undefined}
        >
          <CardGrid shape={shape} label={t("WebLibraryItems")}>
            {items.data.results.map((item) => (
              <li key={item.id}>
                <ItemCard item={item} shape={shape} />
              </li>
            ))}
          </CardGrid>
        </div>
      )}

      <Pager
        page={state.page}
        pages={pages}
        hrefFor={(page) => hrefFor({ ...state, page })}
        labels={{
          nav: t("WebPagination"),
          previous: t("WebPrevious"),
          next: t("WebNext"),
          pageOf: t("WebPageOf", state.page, pages),
        }}
      />
    </div>
  );
}
