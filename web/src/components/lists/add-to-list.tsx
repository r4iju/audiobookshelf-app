"use client";

import { Check, Plus } from "lucide-react";
import type { ReactNode } from "react";
import { z } from "zod";
import { InlineError } from "@/components/app/inline-error";
import { Button } from "@/components/ui/button";
import { Dialog } from "@/components/ui/dialog";
import { TextField } from "@/components/ui/field";
import { QueryState } from "@/components/ui/query-state";
import { useI18n } from "@/i18n/i18n";
import {
  type PlaylistEntry,
  useAddToCollection,
  useAddToPlaylist,
  useCreateCollection,
  useCreatePlaylist,
  useRemoveFromCollection,
  useRemoveFromPlaylist,
} from "@/lib/abs/mutations";
import { useCollections, usePlaylists } from "@/lib/abs/queries";

const newListSchema = z.object({ name: z.string().trim().min(1) });

interface ListChoice {
  id: string;
  name: string;
  contains: boolean;
}

/** Both kinds of list: toggle membership in existing lists or start a new one. */
function ListChooser({
  newLabel,
  emptyLabel,
  choices,
  busy,
  error,
  onToggle,
  onCreate,
}: {
  newLabel: string;
  emptyLabel: string;
  choices: ListChoice[];
  busy: boolean;
  error: Error | null;
  onToggle: (choice: ListChoice) => void;
  onCreate: (name: string) => void;
}) {
  const { t } = useI18n();
  return (
    <>
      {choices.length ? (
        <ul className="flex max-h-72 flex-col gap-1 overflow-y-auto">
          {choices.map((choice) => (
            <li
              key={choice.id}
              className="flex items-center gap-3 rounded-xl bg-surface-2 py-1.5 ps-3 pe-1.5"
            >
              <span className="min-w-0 flex-1 truncate text-sm font-medium">{choice.name}</span>
              <Button
                size="sm"
                variant={choice.contains ? "ghost" : "secondary"}
                disabled={busy}
                aria-label={
                  choice.contains ? t("WebRemoveFromNamed", choice.name) : t("WebAddToNamed", choice.name)
                }
                onClick={() => onToggle(choice)}
              >
                {choice.contains ? (
                  <Check aria-hidden className="size-4" />
                ) : (
                  <Plus aria-hidden className="size-4" />
                )}
                {choice.contains ? t("ButtonRemove") : t("ButtonAdd")}
              </Button>
            </li>
          ))}
        </ul>
      ) : (
        <p className="text-sm text-muted">{emptyLabel}</p>
      )}
      <form
        className="flex items-end gap-2"
        action={(form) => {
          const parsed = newListSchema.safeParse({ name: form.get("name") });
          if (parsed.success) onCreate(parsed.data.name);
        }}
      >
        <TextField label={newLabel} name="name" required className="flex-1" autoComplete="off" />
        <Button type="submit" variant="primary" disabled={busy}>
          {t("ButtonCreate")}
        </Button>
      </form>
      <InlineError error={error} />
    </>
  );
}

function ListDialog({
  title,
  onClose,
  children,
}: {
  title: string;
  onClose: () => void;
  children: ReactNode;
}) {
  const { t } = useI18n();
  return (
    <Dialog open onClose={onClose} title={title}>
      {children}
      <div className="flex justify-end">
        <Button variant="ghost" onClick={onClose}>
          {t("WebClose")}
        </Button>
      </div>
    </Dialog>
  );
}

export function AddToPlaylistDialog({
  libraryId,
  entry,
  onClose,
}: {
  libraryId: string;
  entry: PlaylistEntry;
  onClose: () => void;
}) {
  const { t } = useI18n();
  const playlists = usePlaylists(libraryId);
  const create = useCreatePlaylist();
  const add = useAddToPlaylist();
  const remove = useRemoveFromPlaylist();
  return (
    <ListDialog title={t("LabelAddToPlaylist")} onClose={onClose}>
      <QueryState query={playlists}>
        {(data) => (
          <ListChooser
            newLabel={t("HeaderNewPlaylist")}
            emptyLabel={t("MessageNoUserPlaylists")}
            choices={data.map((playlist) => ({
              id: playlist.id,
              name: playlist.name,
              contains: playlist.items.some(
                (item) =>
                  item.libraryItemId === entry.libraryItemId && (item.episodeId ?? null) === entry.episodeId,
              ),
            }))}
            busy={create.isPending || add.isPending || remove.isPending}
            error={create.error ?? add.error ?? remove.error}
            onToggle={(choice) => (choice.contains ? remove : add).mutate({ playlistId: choice.id, entry })}
            onCreate={(name) => create.mutate({ libraryId, name, entry })}
          />
        )}
      </QueryState>
    </ListDialog>
  );
}

export function AddToCollectionDialog({
  libraryId,
  itemId,
  onClose,
}: {
  libraryId: string;
  itemId: string;
  onClose: () => void;
}) {
  const { t } = useI18n();
  const collections = useCollections(libraryId);
  const create = useCreateCollection();
  const add = useAddToCollection();
  const remove = useRemoveFromCollection();
  return (
    <ListDialog title={t("WebAddToCollection")} onClose={onClose}>
      <QueryState query={collections}>
        {(data) => (
          <ListChooser
            newLabel={t("WebNewCollection")}
            emptyLabel={t("MessageNoCollections")}
            choices={data.map((collection) => ({
              id: collection.id,
              name: collection.name,
              contains: collection.books.some((book) => book.id === itemId),
            }))}
            busy={create.isPending || add.isPending || remove.isPending}
            error={create.error ?? add.error ?? remove.error}
            onToggle={(choice) =>
              (choice.contains ? remove : add).mutate({ collectionId: choice.id, itemId })
            }
            onCreate={(name) => create.mutate({ libraryId, name, itemId })}
          />
        )}
      </QueryState>
    </ListDialog>
  );
}
