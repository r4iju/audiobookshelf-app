"use client";

import Link from "next/link";
import { Cover } from "@/components/media/cover";
import { CardGrid } from "@/components/media/item-card";
import { QueryState } from "@/components/ui/query-state";
import { EmptyState } from "@/components/ui/status";
import { useI18n } from "@/i18n/i18n";
import { authorImageUrl } from "@/lib/abs/media";
import { useAuthor, useAuthors } from "@/lib/abs/queries";
import { useAbs } from "@/lib/session/store";
import { htmlToText } from "@/lib/text";
import { AuthorCard, ItemCard } from "./cards";
import { useLibrary } from "./use-library";

export function AuthorsList({ libraryId }: { libraryId: string }) {
  const { t } = useI18n();
  const authors = useAuthors(libraryId);
  return (
    <div className="flex flex-col gap-6">
      <h1 className="text-2xl font-bold tracking-tight lg:text-3xl">{t("LabelAuthors")}</h1>
      <QueryState query={authors}>
        {(data) =>
          data.length === 0 ? (
            <EmptyState title={t("MessageNoItemsFound")} />
          ) : (
            <CardGrid shape="square" label={t("LabelAuthors")}>
              {data.map((author) => (
                <li key={author.id}>
                  <AuthorCard author={author} libraryId={libraryId} />
                </li>
              ))}
            </CardGrid>
          )
        }
      </QueryState>
    </div>
  );
}

export function AuthorDetail({ libraryId, authorId }: { libraryId: string; authorId: string }) {
  const { t } = useI18n();
  const { client } = useAbs();
  const { shape } = useLibrary(libraryId);
  const author = useAuthor(libraryId, authorId);
  return (
    <QueryState query={author}>
      {(data) => {
        const inSeries = new Set(data.series.flatMap((series) => series.items.map((item) => item.id)));
        const standalone = data.libraryItems.filter((item) => !inSeries.has(item.id));
        return (
          <div className="flex flex-col gap-8">
            <header className="flex flex-col gap-5 sm:flex-row sm:items-end">
              <div className="w-36 shrink-0">
                <Cover
                  src={authorImageUrl(client, data)}
                  title={data.name}
                  shape="square"
                  missingLabel={t("WebNoCover")}
                  className="rounded-full"
                />
              </div>
              <div className="flex flex-col gap-2">
                <p className="text-sm font-medium text-muted">{t("LabelAuthor")}</p>
                <h1 className="text-2xl font-bold tracking-tight lg:text-3xl">{data.name}</h1>
                {data.description ? (
                  <p className="max-w-prose whitespace-pre-line text-sm text-muted">
                    {htmlToText(data.description)}
                  </p>
                ) : null}
              </div>
            </header>
            {data.series.map((series) => (
              <section
                key={series.id}
                aria-labelledby={`series-${series.id}`}
                className="flex flex-col gap-3"
              >
                <h2 id={`series-${series.id}`} className="text-lg font-semibold">
                  <Link
                    href={`/library/${libraryId}/series/${series.id}`}
                    className="rounded focus-ring hover:underline"
                  >
                    {series.name}
                  </Link>
                </h2>
                <CardGrid shape={shape}>
                  {series.items.map((item) => (
                    <li key={item.id}>
                      <ItemCard item={item} shape={shape} />
                    </li>
                  ))}
                </CardGrid>
              </section>
            ))}
            {standalone.length ? (
              <section aria-labelledby="author-books" className="flex flex-col gap-3">
                <h2 id="author-books" className="text-lg font-semibold">
                  {t("LabelBooks")}
                </h2>
                <CardGrid shape={shape} label={t("WebLibraryItems")}>
                  {standalone.map((item) => (
                    <li key={item.id}>
                      <ItemCard item={item} shape={shape} />
                    </li>
                  ))}
                </CardGrid>
              </section>
            ) : null}
          </div>
        );
      }}
    </QueryState>
  );
}
