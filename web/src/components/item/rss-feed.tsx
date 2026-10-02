"use client";

import { Check, Copy, Rss } from "lucide-react";
import { useState } from "react";
import { InlineError } from "@/components/app/inline-error";
import { Button } from "@/components/ui/button";
import { Dialog } from "@/components/ui/dialog";
import { TextField, Toggle } from "@/components/ui/field";
import { useI18n } from "@/i18n/i18n";
import { type Feed, feedSlug } from "@/lib/abs/feeds";
import { useCloseFeed, useOpenFeed } from "@/lib/abs/mutations";
import { isAdmin } from "@/lib/abs/permissions";
import type { LibraryItem, User } from "@/lib/abs/schemas";
import { useAbs } from "@/lib/session/store";

/** Like the legacy item menu: anyone sees an open feed's address; only administrators open or close feeds. */
export function canSeeFeed(item: LibraryItem, me: User | undefined) {
  const hasMedia =
    (item.media.tracks?.length ?? item.media.numTracks ?? 0) > 0 || !!item.media.episodes?.length;
  return item.rssFeed ? true : hasMedia && isAdmin(me);
}

export function RssFeedButton({
  item,
  me,
  onClosed,
}: {
  item: LibraryItem;
  me: User | undefined;
  onClosed: () => void;
}) {
  const { t } = useI18n();
  const [open, setOpen] = useState(false);
  return (
    <>
      <Button onClick={() => setOpen(true)}>
        <Rss aria-hidden className="size-4" />
        {item.rssFeed ? t("HeaderRSSFeed") : t("HeaderOpenRSSFeed")}
      </Button>
      {open ? (
        <RssFeedDialog
          item={item}
          admin={isAdmin(me)}
          onClose={() => setOpen(false)}
          onClosed={() => {
            setOpen(false);
            onClosed();
          }}
        />
      ) : null}
    </>
  );
}

function RssFeedDialog({
  item,
  admin,
  onClose,
  onClosed,
}: {
  item: LibraryItem;
  admin: boolean;
  onClose: () => void;
  onClosed: () => void;
}) {
  const { t } = useI18n();
  const openFeed = useOpenFeed(item.id);
  const feed = openFeed.data ?? item.rssFeed ?? null;
  return (
    <Dialog open onClose={onClose} title={feed ? t("HeaderRSSFeedIsOpen") : t("HeaderOpenRSSFeed")}>
      {feed ? (
        <OpenFeed feed={feed} itemId={item.id} admin={admin} onClosed={onClosed} />
      ) : (
        <NewFeed item={item} opening={openFeed} />
      )}
      <div className="flex justify-end">
        <Button variant="ghost" onClick={onClose}>
          {t("WebClose")}
        </Button>
      </div>
    </Dialog>
  );
}

function OpenFeed({
  feed,
  itemId,
  admin,
  onClosed,
}: {
  feed: Feed;
  itemId: string;
  admin: boolean;
  onClosed: () => void;
}) {
  const { t } = useI18n();
  const { client } = useAbs();
  const closeFeed = useCloseFeed(itemId);
  const [copied, setCopied] = useState(false);
  const address = client.url(feed.feedUrl);
  return (
    <>
      <div className="flex items-end gap-2">
        <TextField label={t("HeaderRSSFeed")} value={address} readOnly className="min-w-0 flex-1" />
        <Button
          size="icon"
          variant="ghost"
          aria-label={t("WebCopyAddress")}
          // A plain-HTTP LAN origin has no clipboard; the address stays selectable in the field.
          onClick={() =>
            Promise.resolve()
              .then(() => navigator.clipboard.writeText(address))
              .then(() => setCopied(true))
              .catch(() => {})
          }
        >
          {copied ? <Check aria-hidden className="size-4" /> : <Copy aria-hidden className="size-4" />}
        </Button>
      </div>
      {feed.meta ? (
        <dl className="grid grid-cols-[max-content_1fr] gap-x-4 gap-y-1 text-sm">
          <dt className="text-muted">{t("LabelRSSFeedPreventIndexing")}</dt>
          <dd>{feed.meta.preventIndexing ? t("ButtonYes") : t("LabelNo")}</dd>
          {feed.meta.ownerName ? (
            <>
              <dt className="text-muted">{t("LabelRSSFeedCustomOwnerName")}</dt>
              <dd>{feed.meta.ownerName}</dd>
            </>
          ) : null}
          {feed.meta.ownerEmail ? (
            <>
              <dt className="text-muted">{t("LabelRSSFeedCustomOwnerEmail")}</dt>
              <dd>{feed.meta.ownerEmail}</dd>
            </>
          ) : null}
        </dl>
      ) : null}
      {admin ? (
        <Button
          variant="danger"
          disabled={closeFeed.isPending}
          onClick={() => closeFeed.mutate(feed.id, { onSuccess: onClosed })}
        >
          {t("ButtonCloseFeed")}
        </Button>
      ) : null}
      {closeFeed.error ? (
        <p role="alert" className="text-sm text-danger">
          {t("ToastRSSFeedCloseFailed")}
        </p>
      ) : null}
    </>
  );
}

function NewFeed({ item, opening }: { item: LibraryItem; opening: ReturnType<typeof useOpenFeed> }) {
  const { t } = useI18n();
  const { client } = useAbs();
  const [slug, setSlug] = useState(item.id);
  const [preventIndexing, setPreventIndexing] = useState(true);
  const [ownerName, setOwnerName] = useState("");
  const [ownerEmail, setOwnerEmail] = useState("");
  const cleaned = feedSlug(slug);
  return (
    <form
      className="flex flex-col gap-3"
      action={() => {
        if (cleaned) opening.mutate({ slug: cleaned, preventIndexing, ownerName, ownerEmail });
      }}
    >
      <TextField
        label={t("LabelRSSFeedSlug")}
        value={slug}
        onChange={(event) => setSlug(event.target.value)}
        help={t("MessageFeedURLWillBe", client.url(`/feed/${cleaned}`))}
        required
        autoComplete="off"
      />
      <Toggle
        label={t("LabelRSSFeedPreventIndexing")}
        checked={preventIndexing}
        onChange={(event) => setPreventIndexing(event.target.checked)}
      />
      <TextField
        label={t("LabelRSSFeedCustomOwnerName")}
        value={ownerName}
        onChange={(event) => setOwnerName(event.target.value)}
        autoComplete="off"
      />
      <TextField
        label={t("LabelRSSFeedCustomOwnerEmail")}
        type="email"
        value={ownerEmail}
        onChange={(event) => setOwnerEmail(event.target.value)}
        autoComplete="off"
      />
      {client.connection.serverUrl.startsWith("http://") ? (
        <p className="text-xs text-muted">{t("NoteRSSFeedPodcastAppsHttps")}</p>
      ) : null}
      {item.media.episodes?.some((episode) => !episode.pubDate) ? (
        <p className="text-xs text-muted">{t("NoteRSSFeedPodcastAppsPubDate")}</p>
      ) : null}
      <Button type="submit" variant="primary" disabled={!cleaned || opening.isPending}>
        {t("ButtonOpenFeed")}
      </Button>
      <InlineError error={opening.error} />
    </form>
  );
}
