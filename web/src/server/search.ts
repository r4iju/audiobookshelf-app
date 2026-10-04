import "server-only";
import { z } from "zod";
import { searchResultsSchema } from "@/lib/abs/schemas";
import { MAX_SEARCH_RESULTS } from "@/lib/abs/search-limits";
import type { Account } from "./accounts";
import { itemsFor } from "./catalog";

export function searchLibrary(actor: Account, libraryId: string, params: URLSearchParams) {
  const items = itemsFor(actor, libraryId);
  const query = z
    .string()
    .max(1024)
    .parse(params.get("q") ?? "")
    .trim()
    .normalize("NFKC")
    .toLowerCase();
  const limit = z.coerce
    .number()
    .int()
    .min(1)
    .max(MAX_SEARCH_RESULTS + 1)
    .parse(params.get("limit") ?? 12);
  const words = query.split(/\s+/).filter(Boolean);
  const matches = (value: string) => {
    const text = value.normalize("NFKC").toLowerCase();
    return words.length > 0 && words.every((word) => text.includes(word));
  };
  const found = items.filter((item) => {
    const metadata = item.media.metadata;
    return matches([metadata.title, metadata.subtitle ?? "", metadata.description ?? ""].join(" "));
  });
  const authors = [
    ...new Map(
      items.flatMap((item) => item.media.metadata.authors ?? []).map((author) => [author.id, author]),
    ).values(),
  ];
  const series = [
    ...new Map(
      items.flatMap((item) => item.media.metadata.series ?? []).map((series) => [series.id, series]),
    ).values(),
  ];
  const names = (values: string[], kind: "tags" | "genres" | "narrators") =>
    [...new Set(values)]
      .filter(matches)
      .sort()
      .slice(0, limit)
      .map((name) => ({
        name,
        ...(kind === "narrators"
          ? { numBooks: items.filter((item) => item.media.metadata.narrators?.includes(name)).length }
          : {
              numItems: items.filter((item) =>
                (kind === "tags" ? item.media.tags : item.media.metadata.genres).includes(name),
              ).length,
            }),
      }));
  return searchResultsSchema.parse({
    book: found
      .filter((item) => item.mediaType === "book")
      .slice(0, limit)
      .map((libraryItem) => ({ libraryItem })),
    podcast: found
      .filter((item) => item.mediaType === "podcast")
      .slice(0, limit)
      .map((libraryItem) => ({ libraryItem })),
    episodes: [],
    authors: authors
      .filter((author) => matches(author.name))
      .slice(0, limit)
      .map((author) => ({
        ...author,
        numBooks: items.filter((item) => item.media.metadata.authors?.some((value) => value.id === author.id))
          .length,
      })),
    series: series
      .filter((series) => matches(series.name))
      .slice(0, limit)
      .map((series) => ({
        series,
        books: items.filter((item) => item.media.metadata.series?.some((value) => value.id === series.id)),
      })),
    narrators: names(
      items.flatMap((item) => item.media.metadata.narrators ?? []),
      "narrators",
    ),
    tags: names(
      items.flatMap((item) => item.media.tags),
      "tags",
    ),
    genres: names(
      items.flatMap((item) => item.media.metadata.genres),
      "genres",
    ),
  });
}
