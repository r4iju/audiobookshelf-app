import "server-only";
import { z } from "zod";
import { type LibraryItem, mediaProgressSchema } from "@/lib/abs/schemas";
import { type Account, DomainError } from "./accounts";
import { findLibrary, itemsFor, librariesFor } from "./catalog";
import { database } from "./data";

function sequence(item: LibraryItem, id: string) {
  const value = item.media.metadata.series?.find((ref) => ref.id === id)?.sequence;
  return value != null && value !== "" && Number.isFinite(Number(value)) ? Number(value) : Infinity;
}
function orderedBooks(items: LibraryItem[], seriesId: string) {
  return [...items].sort(
    (a, b) =>
      sequence(a, seriesId) - sequence(b, seriesId) ||
      a.media.metadata.title.localeCompare(b.media.metadata.title, undefined, { numeric: true }) ||
      a.id.localeCompare(b.id),
  );
}
export function authorGroups(items: LibraryItem[]) {
  const groups = new Map<string, { id: string; name: string; description: null; numBooks: number }>();
  for (const item of items)
    for (const ref of new Map((item.media.metadata.authors ?? []).map((ref) => [ref.id, ref])).values()) {
      const group = groups.get(ref.id) ?? { id: ref.id, name: ref.name, description: null, numBooks: 0 };
      group.numBooks++;
      groups.set(ref.id, group);
    }
  return [...groups.values()].sort((a, b) => a.name.localeCompare(b.name) || a.id.localeCompare(b.id));
}
export function seriesGroups(items: LibraryItem[]) {
  const groups = new Map<string, { id: string; name: string; description: null; books: LibraryItem[] }>();
  for (const item of items)
    for (const ref of item.media.metadata.series ?? []) {
      const group = groups.get(ref.id) ?? { id: ref.id, name: ref.name, description: null, books: [] };
      if (!group.books.some((book) => book.id === item.id)) group.books.push(item);
      groups.set(ref.id, group);
    }
  return [...groups.values()]
    .map((group) => ({ ...group, books: orderedBooks(group.books, group.id), numBooks: group.books.length }))
    .sort((a, b) => a.name.localeCompare(b.name, undefined, { numeric: true }) || a.id.localeCompare(b.id));
}
export function pagedSeries(actor: Account, libraryId: string, params: URLSearchParams) {
  const limit = z.coerce
      .number()
      .int()
      .min(1)
      .max(10000)
      .parse(params.get("limit") ?? 50),
    page = z.coerce
      .number()
      .int()
      .min(0)
      .max(100000)
      .parse(params.get("page") ?? 0);
  const sort = z.enum(["name", "numBooks"]).parse(params.get("sort") ?? "name");
  const groups = seriesGroups(itemsFor(actor, libraryId));
  if (sort === "numBooks") groups.sort((a, b) => a.numBooks - b.numBooks || a.id.localeCompare(b.id));
  if (params.get("desc") === "1") groups.reverse();
  return { results: groups.slice(page * limit, (page + 1) * limit), total: groups.length, page, limit };
}
export function seriesFor(actor: Account, libraryId: string, id: string) {
  const group = seriesGroups(itemsFor(actor, libraryId)).find((group) => group.id === id);
  if (!group) throw new DomainError(404, "Not found");
  return group;
}
export function authorFor(actor: Account, id: string, libraryId: string | null) {
  const items = libraryId
    ? itemsFor(actor, libraryId)
    : librariesFor(actor).flatMap((library) => itemsFor(actor, library.id));
  const author = authorGroups(items).find((author) => author.id === id);
  if (!author) throw new DomainError(404, "Not found");
  const books = items.filter((item) => item.media.metadata.authors?.some((ref) => ref.id === id));
  return {
    ...author,
    libraryItems: books,
    series: seriesGroups(books).map((group) => ({ id: group.id, name: group.name, items: group.books })),
  };
}
export function personalized(actor: Account, libraryId: string, params: URLSearchParams) {
  const items = itemsFor(actor, libraryId),
    limit = z.coerce
      .number()
      .int()
      .min(1)
      .max(200)
      .parse(params.get("limit") ?? 20);
  if (findLibrary(libraryId).mediaType === "podcast") {
    const states = new Map(
      database()
        .prepare("SELECT item_id,episode_id,content FROM media_progress WHERE user_id=? AND episode_id<>''")
        .all(actor.id)
        .map((row) => [
          JSON.stringify([String(row.item_id), String(row.episode_id)]),
          mediaProgressSchema.parse(JSON.parse(z.string().parse(row.content))),
        ]),
    );
    const episodes = items
      .filter((item) => !item.isMissing && !item.isInvalid)
      .flatMap((item) =>
        (item.media.episodes ?? [])
          .filter((episode) => episode.audioFile)
          .map((episode) => ({
            item: { ...item, recentEpisode: episode },
            state: states.get(JSON.stringify([item.id, episode.id])),
          })),
      );
    const shelf = (id: string, label: string, labelStringKey: string, entries: typeof episodes) => ({
      id,
      label,
      labelStringKey,
      type: "episode",
      entities: entries.slice(0, limit).map((entry) => entry.item),
    });
    return [
      shelf(
        "continue-listening",
        "Continue listening",
        "LabelContinueListening",
        episodes
          .filter(
            ({ state }) =>
              state &&
              !state.isFinished &&
              !state.hideFromContinueListening &&
              (state.progress > 0 || state.currentTime > 0),
          )
          .sort(
            (a, b) =>
              (b.state?.lastUpdate ?? 0) - (a.state?.lastUpdate ?? 0) ||
              a.item.recentEpisode.id.localeCompare(b.item.recentEpisode.id),
          ),
      ),
      {
        id: "recently-added",
        label: "Recently added",
        labelStringKey: "LabelRecentlyAdded",
        type: "podcast",
        entities: [...items]
          .sort((a, b) => (b.addedAt ?? 0) - (a.addedAt ?? 0) || a.id.localeCompare(b.id))
          .slice(0, limit),
      },
      shelf(
        "recently-finished",
        "Listen again",
        "LabelListenAgain",
        episodes
          .filter(({ state }) => state?.isFinished)
          .sort(
            (a, b) =>
              (b.state?.finishedAt ?? 0) - (a.state?.finishedAt ?? 0) ||
              a.item.recentEpisode.id.localeCompare(b.item.recentEpisode.id),
          ),
      ),
    ];
  }
  const progress = new Map(
    database()
      .prepare("SELECT item_id,content FROM media_progress WHERE user_id=? AND episode_id=''")
      .all(actor.id)
      .map((row) => [
        z.string().parse(row.item_id),
        mediaProgressSchema.parse(JSON.parse(z.string().parse(row.content))),
      ]),
  );
  const type = items[0]?.mediaType ?? "book";
  const shelf = (id: string, label: string, labelStringKey: string, entities: LibraryItem[]) => ({
    id,
    label,
    labelStringKey,
    type,
    entities: entities.slice(0, limit),
  });
  const resumable = items
    .filter((item) => {
      const state = progress.get(item.id);
      return (
        !item.isMissing &&
        !item.isInvalid &&
        state &&
        !state.isFinished &&
        !state.hideFromContinueListening &&
        (state.progress > 0 || state.currentTime > 0 || Boolean(state.ebookLocation))
      );
    })
    .sort(
      (a, b) =>
        (progress.get(b.id)?.lastUpdate ?? 0) - (progress.get(a.id)?.lastUpdate ?? 0) ||
        a.id.localeCompare(b.id),
    );
  const finished = items
    .filter((item) => progress.get(item.id)?.isFinished)
    .sort(
      (a, b) =>
        (progress.get(b.id)?.finishedAt ?? 0) - (progress.get(a.id)?.finishedAt ?? 0) ||
        a.id.localeCompare(b.id),
    );
  return [
    shelf(
      "continue-listening",
      "Continue listening",
      "LabelContinueListening",
      resumable.filter((item) => Boolean(item.media.tracks?.length)),
    ),
    shelf(
      "continue-reading",
      "Continue reading",
      "LabelContinueReading",
      resumable.filter((item) => Boolean(item.media.ebookFile && progress.get(item.id)?.ebookLocation)),
    ),
    shelf(
      "recently-added",
      "Recently added",
      "LabelRecentlyAdded",
      [...items].sort((a, b) => (b.addedAt ?? 0) - (a.addedAt ?? 0) || a.id.localeCompare(b.id)),
    ),
    shelf("recently-finished", "Listen again", "LabelListenAgain", finished),
  ];
}
