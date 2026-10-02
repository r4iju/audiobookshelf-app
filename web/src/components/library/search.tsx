"use client";

import { Search as SearchIcon } from "lucide-react";
import Link from "next/link";
import { usePathname, useRouter } from "next/navigation";
import { type ReactNode, useRef } from "react";
import { CardGrid } from "@/components/media/item-card";
import { QueryState } from "@/components/ui/query-state";
import { EmptyState } from "@/components/ui/status";
import { useI18n } from "@/i18n/i18n";
import { encodeFilter } from "@/lib/abs/browse";
import { useSearch } from "@/lib/abs/queries";
import { AuthorCard, ItemCard, SeriesCard } from "./cards";
import { useLibrary } from "./use-library";

/** Searches the library for `q`, showing up to `limit` matches of each kind and a link to more when there are. */
export function LibrarySearch({ libraryId, q, limit }: { libraryId: string; q: string; limit: number }) {
  const { t } = useI18n();
  const router = useRouter();
  const pathname = usePathname();
  const { library, shape } = useLibrary(libraryId);
  const results = useSearch(libraryId, q, limit);
  const timer = useRef<ReturnType<typeof setTimeout>>(undefined);

  const onChange = (value: string) => {
    clearTimeout(timer.current);
    timer.current = setTimeout(() => {
      router.replace(value.trim() ? `${pathname}?${new URLSearchParams({ q: value })}` : pathname);
    }, 250);
  };

  return (
    <div className="flex flex-col gap-6">
      <h1 className="sr-only">
        {t("ButtonSearch")} {library?.name}
      </h1>
      <search className="relative">
        <SearchIcon
          aria-hidden
          className="pointer-events-none absolute top-1/2 start-4 size-5 -translate-y-1/2 text-muted"
        />
        <input
          type="search"
          aria-label={t("ButtonSearch")}
          placeholder={t("WebSearchPlaceholder")}
          defaultValue={q}
          onChange={(event) => onChange(event.target.value)}
          // biome-ignore lint/a11y/noAutofocus: the search screen exists to type into this field
          autoFocus
          className="min-h-12 w-full rounded-2xl border border-line bg-surface ps-12 pe-4 text-base focus-ring"
        />
      </search>
      {q.trim() === "" ? (
        <EmptyState title={t("WebSearchMinimum")} />
      ) : (
        <QueryState query={results}>
          {(data) => {
            const items = [...data.book, ...data.podcast].map((entry) => entry.libraryItem);
            const empty =
              items.length +
                data.series.length +
                data.authors.length +
                data.narrators.length +
                data.tags.length +
                data.genres.length ===
              0;
            if (empty) return <EmptyState title={t("MessageNoItemsFound")} />;
            return (
              <div aria-busy={results.isPlaceholderData} className="flex flex-col gap-8">
                {items.length ? (
                  <ResultSection
                    title={library?.mediaType === "podcast" ? t("LabelPodcasts") : t("LabelBooks")}
                  >
                    <CardGrid shape={shape} label={t("WebSearchResults")}>
                      {items.map((item) => (
                        <li key={item.id}>
                          <ItemCard item={item} shape={shape} />
                        </li>
                      ))}
                    </CardGrid>
                  </ResultSection>
                ) : null}
                {data.series.length ? (
                  <ResultSection title={t("LabelSeries")}>
                    <CardGrid shape={shape}>
                      {data.series.map(({ series, books }) => (
                        <li key={series.id}>
                          <SeriesCard series={{ ...series, books }} libraryId={libraryId} shape={shape} />
                        </li>
                      ))}
                    </CardGrid>
                  </ResultSection>
                ) : null}
                {data.authors.length ? (
                  <ResultSection title={t("LabelAuthors")}>
                    <CardGrid shape="square">
                      {data.authors.map((author) => (
                        <li key={author.id}>
                          <AuthorCard author={author} libraryId={libraryId} />
                        </li>
                      ))}
                    </CardGrid>
                  </ResultSection>
                ) : null}
                {(
                  [
                    ["narrators", t("LabelNarrators"), data.narrators],
                    ["tags", t("LabelTags"), data.tags],
                    ["genres", t("LabelGenres"), data.genres],
                  ] as const
                ).map(([group, title, entries]) =>
                  entries.length ? (
                    <ResultSection key={group} title={title}>
                      <ul className="flex flex-wrap gap-2">
                        {entries.map((entry) => (
                          <li key={entry.name}>
                            <Link
                              href={`/library/${libraryId}/items?${new URLSearchParams({ filter: encodeFilter(group, entry.name) })}`}
                              className="inline-flex min-h-9 items-center rounded-full bg-surface-2 px-3 text-sm hover:bg-surface-3 focus-ring"
                            >
                              {entry.name}
                            </Link>
                          </li>
                        ))}
                      </ul>
                    </ResultSection>
                  ) : null,
                )}
                {data.more ? (
                  <Link
                    href={`${pathname}?${new URLSearchParams({ q, limit: String(data.limit * 4) })}`}
                    replace
                    scroll={false}
                    className="inline-flex min-h-11 items-center self-center rounded-full bg-surface-2 px-5 text-sm font-medium hover:bg-surface-3 focus-ring"
                  >
                    {t("LabelMore")}
                  </Link>
                ) : null}
              </div>
            );
          }}
        </QueryState>
      )}
    </div>
  );
}

function ResultSection({ title, children }: { title: string; children: ReactNode }) {
  return (
    <section className="flex flex-col gap-3">
      <h2 className="text-lg font-semibold">{title}</h2>
      {children}
    </section>
  );
}
