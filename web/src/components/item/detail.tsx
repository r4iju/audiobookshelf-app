"use client";

import { BookOpen, FolderPlus, ListPlus, Pause, Play } from "lucide-react";
import Link from "next/link";
import { useEffect, useRef, useState } from "react";
import { useLibrary } from "@/components/library/use-library";
import { AddToCollectionDialog, AddToPlaylistDialog } from "@/components/lists/add-to-list";
import { Cover } from "@/components/media/cover";
import { Button, ButtonLink } from "@/components/ui/button";
import { QueryState } from "@/components/ui/query-state";
import { Alert } from "@/components/ui/status";
import { useI18n } from "@/i18n/i18n";
import { coverShapeOf, coverUrl, formatClock, formatDuration } from "@/lib/abs/media";
import { can } from "@/lib/abs/permissions";
import { useItem, useItemProgress, useMe } from "@/lib/abs/queries";
import type { LibraryItem } from "@/lib/abs/schemas";
import { usePlayer, usePlayerStore } from "@/lib/player/store";
import { useAbs } from "@/lib/session/store";
import { htmlToText } from "@/lib/text";
import { DownloadButton } from "./download";
import { EpisodeList } from "./episodes";
import { playerMediaFor } from "./play-media";
import { ProgressControls, ProgressSummary, remainingTime } from "./progress-controls";
import { canSeeFeed, RssFeedButton } from "./rss-feed";
import { SendEbookButton, type SendResult } from "./send-ebook";

export function ItemDetail({ itemId }: { itemId: string }) {
  const item = useItem(itemId);
  return <QueryState query={item}>{(data) => <ItemView item={data} />}</QueryState>;
}

function ItemView({ item }: { item: LibraryItem }) {
  const { t } = useI18n();
  const { client } = useAbs();
  const { library } = useLibrary(item.libraryId);
  const progress = useItemProgress().data?.get(item.id);
  const player = usePlayer();
  const me = useMe().data;
  const canUpdate = can(me, "update");
  const [adding, setAdding] = useState<"playlist" | "collection" | null>(null);
  const [notice, setNotice] = useState<SendResult | null>(null);
  const isBook = item.mediaType === "book";
  const metadata = item.media.metadata;
  const isPlayingThis =
    player.phase === "active" && player.media.itemId === item.id && player.media.episodeId === null;
  const playing = isPlayingThis && player.status === "playing";
  const hasAudio = (item.media.tracks?.length ?? item.media.numTracks ?? 0) > 0;
  const chapters = item.media.chapters ?? [];
  const description = htmlToText(metadata.description);
  const supplementary = (item.libraryFiles ?? []).filter(
    (file) => file.fileType === "ebook" && file.isSupplementary && file.ino !== item.media.ebookFile?.ino,
  );
  const remaining = remainingTime(progress, item.media.duration ?? 0);
  const play = (startTime?: number) =>
    usePlayerStore.getState().play({ media: playerMediaFor(client, item), startTime });

  return (
    <article className="flex flex-col gap-8">
      <div className="flex flex-col gap-6 md:flex-row md:items-start">
        <div className="w-44 shrink-0 self-center md:w-56 md:self-start">
          <Cover
            src={coverUrl(client, item)}
            title={metadata.title}
            subtitle={metadata.authorName ?? undefined}
            shape={coverShapeOf(library)}
            missingLabel={t("WebNoCover")}
          />
        </div>
        <div className="flex min-w-0 flex-1 flex-col gap-4">
          <header className="flex flex-col gap-1">
            {metadata.series?.length ? (
              <p className="flex flex-wrap gap-x-3 text-sm font-medium">
                {metadata.series.map((series) => (
                  <Link
                    key={series.id}
                    href={`/library/${item.libraryId}/series/${series.id}`}
                    className="rounded text-accent hover:underline focus-ring"
                  >
                    {series.sequence ? `${series.name} #${series.sequence}` : series.name}
                  </Link>
                ))}
              </p>
            ) : null}
            <h1 className="text-2xl font-bold tracking-tight break-words lg:text-4xl">{metadata.title}</h1>
            {metadata.subtitle ? <p className="text-lg text-muted">{metadata.subtitle}</p> : null}
            {metadata.authors?.length ? (
              <p className="flex flex-wrap gap-x-2 text-base">
                {metadata.authors.map((author, index) => (
                  <span key={author.id}>
                    <Link
                      href={`/library/${item.libraryId}/authors/${author.id}`}
                      className="rounded hover:underline focus-ring"
                    >
                      {author.name}
                    </Link>
                    {index < (metadata.authors?.length ?? 0) - 1 ? "," : null}
                  </span>
                ))}
              </p>
            ) : metadata.authorName || metadata.author ? (
              <p className="text-base">{metadata.authorName ?? metadata.author}</p>
            ) : null}
          </header>

          <dl className="grid grid-cols-[max-content_1fr] gap-x-4 gap-y-1 text-sm">
            {metadata.narrators?.length ? (
              <>
                <dt className="text-muted">{t("LabelNarrators")}</dt>
                <dd>{metadata.narrators.join(", ")}</dd>
              </>
            ) : null}
            {item.media.duration ? (
              <>
                <dt className="text-muted">{t("LabelDuration")}</dt>
                <dd>{formatDuration(item.media.duration)}</dd>
              </>
            ) : null}
            {metadata.publishedYear ? (
              <>
                <dt className="text-muted">{t("LabelPublishYear")}</dt>
                <dd>{metadata.publishedYear}</dd>
              </>
            ) : null}
            {metadata.genres.length ? (
              <>
                <dt className="text-muted">{t("LabelGenres")}</dt>
                <dd>{metadata.genres.join(", ")}</dd>
              </>
            ) : null}
          </dl>

          <ProgressSummary progress={progress} duration={item.media.duration ?? 0} />

          {isBook ? <ProgressControls itemId={item.id} progress={progress} /> : null}

          <div className="flex flex-wrap gap-3">
            {hasAudio ? (
              <Button
                variant="primary"
                onClick={() => (playing ? usePlayerStore.getState().pause() : void play())}
              >
                {playing ? <Pause aria-hidden className="size-4" /> : <Play aria-hidden className="size-4" />}
                {playing ? t("ButtonPause") : t("ButtonPlay")}
                {!playing && remaining !== null ? (
                  <span className="font-normal opacity-80">{formatClock(remaining)}</span>
                ) : null}
              </Button>
            ) : null}
            {item.media.ebookFile ? (
              <ButtonLink href={`/read/${item.id}`} variant={hasAudio ? "secondary" : "primary"}>
                <BookOpen aria-hidden className="size-4" />
                {t("ButtonRead")}
              </ButtonLink>
            ) : null}
            {isBook ? (
              <Button onClick={() => setAdding("playlist")}>
                <ListPlus aria-hidden className="size-4" />
                {t("LabelAddToPlaylist")}
              </Button>
            ) : null}
            {isBook && canUpdate ? (
              <Button onClick={() => setAdding("collection")}>
                <FolderPlus aria-hidden className="size-4" />
                {t("WebAddToCollection")}
              </Button>
            ) : null}
            {can(me, "download") ? <DownloadButton itemId={item.id} /> : null}
            {isBook && item.media.ebookFile ? (
              <SendEbookButton itemId={item.id} onResult={setNotice} />
            ) : null}
            {canSeeFeed(item, me) ? (
              <RssFeedButton
                item={item}
                me={me}
                onClosed={() => setNotice({ tone: "info", text: t("ToastRSSFeedCloseSuccess") })}
              />
            ) : null}
          </div>
          {notice ? <Alert tone={notice.tone}>{notice.text}</Alert> : null}

          {description ? <Description text={description} /> : null}
        </div>
      </div>

      {supplementary.length ? (
        <section aria-labelledby="supplementary" className="flex flex-col gap-2">
          <h2 id="supplementary" className="text-lg font-semibold">
            {t("WebSupplementaryEbooks")}
          </h2>
          <ul className="flex flex-col gap-1">
            {supplementary.map((file) => (
              <li key={file.ino}>
                <Link
                  href={`/read/${item.id}?file=${file.ino}`}
                  className="inline-flex items-center gap-2 rounded text-sm hover:underline focus-ring"
                >
                  <BookOpen aria-hidden className="size-4" />
                  {file.metadata.filename}
                </Link>
              </li>
            ))}
          </ul>
        </section>
      ) : null}

      {item.mediaType === "podcast" ? <EpisodeList item={item} /> : null}

      {adding === "playlist" ? (
        <AddToPlaylistDialog
          libraryId={item.libraryId}
          entry={{ libraryItemId: item.id, episodeId: null }}
          onClose={() => setAdding(null)}
        />
      ) : null}
      {adding === "collection" ? (
        <AddToCollectionDialog libraryId={item.libraryId} itemId={item.id} onClose={() => setAdding(null)} />
      ) : null}

      {chapters.length ? (
        <section aria-labelledby="chapters" className="flex flex-col gap-2">
          <h2 id="chapters" className="text-lg font-semibold">
            {t("HeaderChapters")}
          </h2>
          <ol className="divide-y divide-line overflow-hidden rounded-[var(--radius-card)] bg-surface">
            {chapters.map((chapter) => (
              <li key={chapter.id}>
                <button
                  type="button"
                  onClick={() => void play(chapter.start)}
                  className="flex w-full items-center gap-4 px-4 py-3 text-start text-sm hover:bg-surface-2 focus-ring"
                >
                  <span className="min-w-0 flex-1 truncate">{chapter.title}</span>
                  <span className="text-muted tabular-nums">{formatClock(chapter.start)}</span>
                </button>
              </li>
            ))}
          </ol>
        </section>
      ) : null}
    </article>
  );
}

function Description({ text }: { text: string }) {
  const { t } = useI18n();
  const ref = useRef<HTMLParagraphElement>(null);
  const [expanded, setExpanded] = useState(false);
  const [clamped, setClamped] = useState(false);
  // The browser's line clamp decides whether text is hidden, so watch the rendered paragraph.
  useEffect(() => {
    const node = ref.current;
    if (!node || expanded) return;
    const measure = () => setClamped(node.scrollHeight > node.clientHeight);
    measure();
    const observer = new ResizeObserver(measure);
    observer.observe(node);
    return () => observer.disconnect();
  }, [expanded]);
  return (
    <div className="max-w-prose">
      <p
        ref={ref}
        id="item-description"
        className={`whitespace-pre-line text-sm leading-relaxed ${expanded ? "" : "line-clamp-6"}`}
      >
        {text}
      </p>
      {expanded || clamped ? (
        <button
          type="button"
          aria-expanded={expanded}
          aria-controls="item-description"
          onClick={() => setExpanded(!expanded)}
          className="mt-1 rounded text-sm font-medium text-accent focus-ring"
        >
          {expanded ? t("ButtonReadLess") : t("ButtonReadMore")}
        </button>
      ) : null}
    </div>
  );
}
