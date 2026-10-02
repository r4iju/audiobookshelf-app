"use client";

import { Pencil, Trash2 } from "lucide-react";
import { useState } from "react";
import { Button } from "@/components/ui/button";
import { ConfirmDialog, Dialog } from "@/components/ui/dialog";
import { TextField } from "@/components/ui/field";
import { Alert } from "@/components/ui/status";
import { useI18n } from "@/i18n/i18n";
import { formatClock } from "@/lib/abs/media";
import { useDeleteBookmark, useUpdateBookmark } from "@/lib/abs/mutations";
import { useMe } from "@/lib/abs/queries";
import type { Bookmark } from "@/lib/abs/schemas";

/** The book's bookmarks, as in the legacy bookmarks list: choosing one takes the player there. */
export function BookmarksDialog({
  itemId,
  onPick,
  onClose,
}: {
  itemId: string;
  onPick: (time: number) => void;
  onClose: () => void;
}) {
  const { t } = useI18n();
  const me = useMe();
  const update = useUpdateBookmark();
  const remove = useDeleteBookmark();
  const [renaming, setRenaming] = useState<Bookmark | null>(null);
  const [removing, setRemoving] = useState<Bookmark | null>(null);
  const bookmarks = (me.data?.bookmarks ?? [])
    .filter((bookmark) => bookmark.libraryItemId === itemId)
    .sort((a, b) => a.time - b.time);

  return (
    <>
      <Dialog open onClose={onClose} title={t("LabelYourBookmarks")}>
        {renaming ? (
          <form
            className="flex flex-col gap-4"
            onSubmit={(event) => {
              event.preventDefault();
              const title = String(new FormData(event.currentTarget).get("title") ?? "").trim();
              if (!title) return;
              update.mutate({ itemId, time: renaming.time, title }, { onSuccess: () => setRenaming(null) });
            }}
          >
            <TextField
              label={t("LabelTitle")}
              name="title"
              defaultValue={renaming.title}
              required
              autoFocus
            />
            {update.isError ? <Alert>{t("ToastBookmarkUpdateFailed")}</Alert> : null}
            <div className="flex justify-end gap-2">
              <Button type="button" variant="ghost" onClick={() => setRenaming(null)}>
                {t("ButtonCancel")}
              </Button>
              <Button type="submit" variant="primary" disabled={update.isPending}>
                {t("ButtonSave")}
              </Button>
            </div>
          </form>
        ) : (
          <>
            {bookmarks.length ? (
              <ul className="flex max-h-[60vh] flex-col gap-1 overflow-y-auto">
                {bookmarks.map((bookmark) => (
                  <li key={bookmark.time} className="flex items-center gap-1">
                    <button
                      type="button"
                      onClick={() => onPick(bookmark.time)}
                      className="flex min-h-11 min-w-0 flex-1 flex-col items-start rounded-xl px-3 py-2 text-start hover:bg-surface-2 focus-ring"
                    >
                      <span className="w-full truncate text-sm font-medium">{bookmark.title}</span>
                      <span className="text-xs text-muted tabular-nums">{formatClock(bookmark.time)}</span>
                    </button>
                    <Button
                      size="icon"
                      variant="ghost"
                      aria-label={t("WebRenameBookmark", bookmark.title)}
                      onClick={() => setRenaming(bookmark)}
                    >
                      <Pencil aria-hidden className="size-4" />
                    </Button>
                    <Button
                      size="icon"
                      variant="ghost"
                      aria-label={`${t("ButtonRemove")} ${bookmark.title}`}
                      onClick={() => setRemoving(bookmark)}
                    >
                      <Trash2 aria-hidden className="size-4" />
                    </Button>
                  </li>
                ))}
              </ul>
            ) : (
              <p className="py-6 text-center text-sm text-muted">{t("MessageNoBookmarks")}</p>
            )}
            {remove.isError ? <Alert>{t("ToastBookmarkRemoveFailed")}</Alert> : null}
          </>
        )}
      </Dialog>
      <ConfirmDialog
        open={removing !== null}
        title={t("ButtonRemove")}
        body={t("MessageConfirmRemoveBookmark")}
        confirmLabel={t("ButtonRemove")}
        cancelLabel={t("ButtonCancel")}
        busy={remove.isPending}
        onConfirm={() => {
          if (removing)
            remove.mutate({ itemId, time: removing.time }, { onSettled: () => setRemoving(null) });
        }}
        onClose={() => setRemoving(null)}
      />
    </>
  );
}
