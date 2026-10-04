"use client";

import { useRouter } from "next/navigation";
import { useLibrary } from "@/components/library/use-library";
import { CardGrid, MediaCard } from "@/components/media/item-card";
import { QueryState } from "@/components/ui/query-state";
import { EmptyState } from "@/components/ui/status";
import { useI18n } from "@/i18n/i18n";
import { coverUrl } from "@/lib/abs/media";
import { useDeleteCollection, useRemoveFromCollection } from "@/lib/abs/mutations";
import { can } from "@/lib/abs/permissions";
import { useCollection, useCollections, useMe } from "@/lib/abs/queries";
import { useAbs } from "@/lib/session/store";
import { bookEntry } from "./entries";
import { ListDetail } from "./list-detail";
import { ListEditor } from "./list-editor";

export function CollectionList({ libraryId }: { libraryId: string }) {
  const { t } = useI18n();
  const { client } = useAbs();
  const { shape } = useLibrary(libraryId);
  const collections = useCollections(libraryId);
  return (
    <div className="flex flex-col gap-6">
      <h1 className="text-2xl font-bold tracking-tight lg:text-3xl">{t("ButtonCollections")}</h1>
      <QueryState query={collections}>
        {(data) =>
          data.length === 0 ? (
            <EmptyState title={t("MessageNoCollections")} />
          ) : (
            <CardGrid shape={shape} label={t("ButtonCollections")}>
              {data.map((collection) => {
                const first = collection.books[0];
                return (
                  <li key={collection.id}>
                    <MediaCard
                      href={`/collection/${collection.id}`}
                      title={collection.name}
                      subtitle={t("WebItemsCount", collection.books.length)}
                      cover={first ? coverUrl(client, first) : null}
                      shape={shape}
                      badge={String(collection.books.length)}
                      progressLabel={t("LabelProgress")}
                      finishedLabel={t("LabelFinished")}
                      missingCoverLabel={t("WebNoCover")}
                    />
                  </li>
                );
              })}
            </CardGrid>
          )
        }
      </QueryState>
    </div>
  );
}

export function CollectionDetail({ collectionId }: { collectionId: string }) {
  const { t } = useI18n();
  const { client } = useAbs();
  const router = useRouter();
  const collection = useCollection(collectionId);
  useLibrary(collection.data?.libraryId);
  const me = useMe().data;
  const remove = useRemoveFromCollection();
  const deleteCollection = useDeleteCollection();
  return (
    <QueryState query={collection}>
      {(data) => (
        <ListDetail
          editor={can(me, "update") ? <ListEditor kind="collection" list={data} /> : undefined}
          name={data.name}
          description={data.description}
          label={t("HeaderCollectionItems")}
          entries={data.books.map((book) => bookEntry(client, book))}
          remove={
            can(me, "update")
              ? {
                  label: (title) => t("WebRemoveNamedFromCollection", title),
                  run: (entry) => remove.mutate({ collectionId, itemId: entry.libraryItemId }),
                }
              : undefined
          }
          deletion={
            can(me, "delete")
              ? {
                  label: t("WebDeleteCollection"),
                  run: () =>
                    deleteCollection.mutate(collectionId, {
                      onSuccess: () => router.replace(`/library/${data.libraryId}/collections`),
                    }),
                }
              : undefined
          }
          busy={remove.isPending || deleteCollection.isPending}
          error={remove.error ?? deleteCollection.error}
        />
      )}
    </QueryState>
  );
}
