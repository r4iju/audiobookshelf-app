"use client";

import { Search } from "lucide-react";
import { usePathname, useRouter } from "next/navigation";
import { useId, useState } from "react";
import { z } from "zod";
import { errorMessage } from "@/components/app/errors";
import { MediaRow } from "@/components/media/media-row";
import { Button } from "@/components/ui/button";
import { SelectField, TextField, Toggle } from "@/components/ui/field";
import { QueryState } from "@/components/ui/query-state";
import { Alert, EmptyState, Spinner } from "@/components/ui/status";
import { useI18n } from "@/i18n/i18n";
import { AbsError } from "@/lib/abs/client";
import { podcastFolderPath } from "@/lib/abs/episodes";
import { useCreatePodcast } from "@/lib/abs/mutations";
import { isAdmin } from "@/lib/abs/permissions";
import { useMe, usePodcastFeed, usePodcastSearch } from "@/lib/abs/queries";
import type { Library, PodcastFeed, PodcastSearchResult } from "@/lib/abs/schemas";
import { useLibrary } from "./use-library";

const isFeedAddress = (value: string) => /^https?:\/\//i.test(value.trim());

/** Search the server's podcast directory or read a feed through the server, then create the podcast there. */
export function AddPodcast({ libraryId, q, feed }: { libraryId: string; q: string; feed: string }) {
  const { t } = useI18n();
  const router = useRouter();
  const pathname = usePathname();
  const me = useMe();
  const { library, libraries } = useLibrary(libraryId);
  const term = q.trim();
  const feedUrl = feed || (isFeedAddress(term) ? term : "");
  const search = usePodcastSearch(term && !isFeedAddress(term) ? term : null);
  const chosen = search.data?.find((result) => result.feedUrl === feedUrl);
  const hrefFor = (params: Record<string, string>) => `${pathname}?${new URLSearchParams(params)}`;

  if (me.isPending || libraries.isPending) return <Spinner label={t("MessageLoading")} />;
  if (me.isError || libraries.isError) return <Alert>{errorMessage(t, me.error ?? libraries.error)}</Alert>;
  if (!library) return <Alert>{t("WebNotFound")}</Alert>;
  if (!isAdmin(me.data) || library.mediaType !== "podcast") return <Alert>{t("WebForbidden")}</Alert>;

  return (
    <div className="flex max-w-3xl flex-col gap-6">
      <h1 className="text-2xl font-bold tracking-tight lg:text-3xl">{t("WebAddPodcast")}</h1>
      <search>
        <form
          className="flex items-end gap-2"
          action={(form) => router.replace(hrefFor({ q: String(form.get("q") ?? "") }))}
        >
          <TextField
            label={t("MessagePodcastSearchField")}
            name="q"
            type="search"
            required
            defaultValue={q}
            className="flex-1"
            autoComplete="off"
          />
          <Button type="submit" variant="primary">
            <Search aria-hidden className="size-4" />
            {t("ButtonSearch")}
          </Button>
        </form>
      </search>

      {feedUrl ? (
        <FeedPreview library={library} feedUrl={feedUrl} directory={chosen} />
      ) : term ? (
        <QueryState query={search}>
          {(results) =>
            results.length === 0 ? (
              <EmptyState title={t("MessageNoPodcastsFound")} />
            ) : (
              <ul
                aria-label={t("WebSearchResults")}
                className="divide-y divide-line overflow-hidden rounded-[var(--radius-card)] bg-surface"
              >
                {results.flatMap((result) =>
                  result.feedUrl
                    ? [
                        <MediaRow
                          key={result.feedUrl}
                          href={hrefFor({ q, feed: result.feedUrl })}
                          cover={result.cover ?? null}
                          title={result.title}
                          subtitle={result.artistName ?? undefined}
                          meta={result.genres.join(", ")}
                          missingCoverLabel={t("WebNoCover")}
                        />,
                      ]
                    : [],
                )}
              </ul>
            )
          }
        </QueryState>
      ) : null}
    </div>
  );
}

function FeedPreview({
  library,
  feedUrl,
  directory,
}: {
  library: Library;
  feedUrl: string;
  directory: PodcastSearchResult | undefined;
}) {
  const { t } = useI18n();
  const podcastFeed = usePodcastFeed(feedUrl);
  if (podcastFeed.isPending) return <Spinner label={t("MessageLoading")} />;
  // The server answers 404 or 400 when it cannot fetch or parse the feed; that is not a missing page here.
  if (podcastFeed.isError)
    return (
      <Alert
        action={
          <Button size="sm" onClick={() => podcastFeed.refetch()}>
            {t("WebRetry")}
          </Button>
        }
      >
        {podcastFeed.error instanceof AbsError &&
        (podcastFeed.error.status === 400 || podcastFeed.error.status === 404)
          ? t("WebFeedUnreadable")
          : errorMessage(t, podcastFeed.error)}
      </Alert>
    );
  return (
    <NewPodcastForm
      key={feedUrl}
      library={library}
      feed={podcastFeed.data}
      feedUrl={feedUrl}
      directory={directory}
    />
  );
}

const newPodcastSchema = z.object({
  title: z.string().trim().min(1),
  author: z.string().trim(),
  description: z.string().trim(),
  folderId: z.string().min(1),
  autoDownloadEpisodes: z.literal("on").optional(),
});

function NewPodcastForm({
  library,
  feed,
  feedUrl,
  directory,
}: {
  library: Library;
  feed: PodcastFeed;
  feedUrl: string;
  directory: PodcastSearchResult | undefined;
}) {
  const { t } = useI18n();
  const router = useRouter();
  const descriptionId = useId();
  const create = useCreatePodcast();
  const metadata = feed.podcast.metadata;
  const initial = { title: directory?.title ?? metadata.title, folderId: library.folders[0]?.id ?? "" };
  const [pathPreview, setPathPreview] = useState(initial);
  const folder = library.folders.find((entry) => entry.id === pathPreview.folderId);
  const path = folder ? podcastFolderPath(folder.fullPath, pathPreview.title) : null;

  return (
    <form
      className="flex flex-col gap-4 rounded-[var(--radius-card)] bg-surface p-5"
      onChange={(event) => {
        const form = new FormData(event.currentTarget);
        setPathPreview({
          title: String(form.get("title") ?? ""),
          folderId: String(form.get("folderId") ?? ""),
        });
      }}
      action={(form) => {
        const parsed = newPodcastSchema.safeParse(Object.fromEntries(form));
        const target = parsed.success
          ? library.folders.find((entry) => entry.id === parsed.data.folderId)
          : null;
        const podcastPath =
          parsed.success && target ? podcastFolderPath(target.fullPath, parsed.data.title) : null;
        if (!parsed.success || !podcastPath) return;
        create.mutate(
          {
            libraryId: library.id,
            folderId: parsed.data.folderId,
            path: podcastPath,
            autoDownloadEpisodes: parsed.data.autoDownloadEpisodes === "on",
            metadata: {
              title: parsed.data.title,
              author: parsed.data.author,
              description: parsed.data.description,
              feedUrl: metadata.feedUrl ?? feedUrl,
              imageUrl: directory?.cover ?? metadata.image ?? "",
              genres: directory?.genres.length ? directory.genres : (metadata.categories ?? []),
              language: directory?.language ?? metadata.language ?? "",
              releaseDate: directory?.releaseDate ?? "",
              itunesPageUrl: directory?.pageUrl ?? "",
              itunesId: directory?.id ? String(directory.id) : "",
              itunesArtistId: directory?.artistId ? String(directory.artistId) : "",
            },
          },
          { onSuccess: (item) => router.push(`/item/${item.id}`) },
        );
      }}
    >
      <TextField label={t("LabelTitle")} name="title" required defaultValue={initial.title} />
      <TextField
        label={t("LabelAuthor")}
        name="author"
        defaultValue={directory?.artistName ?? metadata.author ?? ""}
      />
      <div className="flex flex-col gap-1.5">
        <label htmlFor={descriptionId} className="text-sm font-medium">
          {t("LabelDescription")}
        </label>
        <textarea
          id={descriptionId}
          name="description"
          rows={4}
          defaultValue={directory?.description ?? metadata.descriptionPlain ?? metadata.description ?? ""}
          className="rounded-xl border border-line bg-surface px-3 py-2 text-base text-fg focus-ring"
        />
      </div>
      <TextField label={t("LabelFeedURL")} value={metadata.feedUrl ?? feedUrl} readOnly />
      <SelectField label={t("LabelFolder")} name="folderId" defaultValue={initial.folderId} required>
        {library.folders.map((entry) => (
          <option key={entry.id} value={entry.id}>
            {entry.fullPath}
          </option>
        ))}
      </SelectField>
      <p className="text-sm text-muted break-all">
        {path ? t("WebPodcastSavedTo", path) : t("WebNoPodcastFolder")}
      </p>
      <Toggle label={t("LabelAutoDownloadEpisodes")} name="autoDownloadEpisodes" />
      <p className="text-sm text-muted">{t("WebEpisodesCount", feed.podcast.episodes.length)}</p>
      {create.error ? <Alert>{errorMessage(t, create.error)}</Alert> : null}
      <div className="flex justify-end">
        <Button type="submit" variant="primary" disabled={!path || create.isPending}>
          {t("ButtonCreate")}
        </Button>
      </div>
    </form>
  );
}
