"use client";

import { usePathname, useRouter } from "next/navigation";
import { errorMessage } from "@/components/app/errors";
import { CardGrid } from "@/components/media/item-card";
import { Button } from "@/components/ui/button";
import { InlineToggle } from "@/components/ui/field";
import { SelectField } from "@/components/ui/select";
import { Alert, EmptyState, Spinner } from "@/components/ui/status";
import { type Translate, useI18n } from "@/i18n/i18n";
import { type BrowseState, browseToParams, encodeFilter, naturalDesc, sortsFor } from "@/lib/abs/browse";
import { PAGE_SIZE, useFilterData, useItems } from "@/lib/abs/queries";
import type { FilterData, Library } from "@/lib/abs/schemas";
import { useSettings, useSettingsStore } from "@/lib/settings/store";
import { ItemCard } from "./cards";
import { ListViewToggle } from "./list-view-toggle";
import { Pager } from "./pager";
import { SortDirection } from "./sort-direction";
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
  const { t } = useI18n();
  const router = useRouter();
  const pathname = usePathname();
  const settings = useSettings();
  const updateSettings = useSettingsStore((state) => state.update);
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
  const layout = settings.bookshelfListView ? "list" : "grid";
  const groups = filterGroups(t, mediaType, filterData.data?.filterdata);

  return (
    <div className="flex flex-col gap-6">
      <header className="flex flex-wrap items-end justify-between gap-4">
        <div>
          <h1 className="text-2xl font-bold tracking-tight lg:text-3xl">
            {library?.name ?? t("ButtonLibrary")}
          </h1>
          <div className="flex flex-wrap items-center gap-x-4">
            {items.data ? <p className="text-sm text-muted">{t("WebItemsCount", total)}</p> : null}
            {mediaType === "book" ? (
              <InlineToggle
                label={t("LabelCollapseSeries")}
                checked={settings.collapseSeries}
                onChange={(checked) => {
                  updateSettings({ collapseSeries: checked });
                  if (state.page > 1) go({});
                }}
              />
            ) : null}
          </div>
        </div>
        <div className="flex w-full flex-wrap items-end gap-3 sm:w-auto">
          <div className="flex w-full items-end gap-2 sm:w-auto">
            <SelectField
              label={t("WebSortBy")}
              value={state.sort}
              options={sortsFor(mediaType).map(([value, label]) => ({ value, label: t(label) }))}
              onChange={(sort) => go({ sort, desc: naturalDesc(sort) })}
              className="min-w-0 flex-1 sm:w-48 sm:flex-none"
            />
            <SortDirection desc={state.desc} onChange={(desc) => go({ desc })} />
          </div>
          <div className="flex w-full items-end gap-2 sm:w-auto">
            <SelectField
              label={t("WebFilterBy")}
              value={state.filter ?? ""}
              options={[{ value: "", label: t("LabelAll") }, ...groups]}
              onChange={(filter) => go({ filter: filter || null })}
              className="min-w-0 flex-1 sm:w-48 sm:flex-none"
            />
            <ListViewToggle />
          </div>
        </div>
      </header>

      {items.isPending ? (
        <Spinner label={t("MessageLoading")} />
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
          <CardGrid shape={shape} label={t("WebLibraryItems")} layout={layout}>
            {items.data.results.map((item) => (
              <li key={item.id}>
                <ItemCard item={item} shape={shape} layout={layout} />
              </li>
            ))}
          </CardGrid>
        </div>
      )}

      <Pager page={state.page} pages={pages} hrefFor={(page) => hrefFor({ ...state, page })} />
    </div>
  );
}
