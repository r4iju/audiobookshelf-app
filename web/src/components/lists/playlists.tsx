"use client";

import { useRouter } from "next/navigation";
import { useLibrary } from "@/components/library/use-library";
import { CardGrid, MediaCard } from "@/components/media/item-card";
import { QueryState } from "@/components/ui/query-state";
import { EmptyState } from "@/components/ui/status";
import { useI18n } from "@/i18n/i18n";
import { coverUrl } from "@/lib/abs/media";
import { useDeletePlaylist, useRemoveFromPlaylist } from "@/lib/abs/mutations";
import { usePlaylist, usePlaylists } from "@/lib/abs/queries";
import { useAbs } from "@/lib/session/store";
import { playlistEntries } from "./entries";
import { ListDetail } from "./list-detail";

export function PlaylistList({ libraryId }: { libraryId: string }) {
  const { t } = useI18n();
  const { client } = useAbs();
  const { shape } = useLibrary(libraryId);
  const playlists = usePlaylists(libraryId);
  return (
    <div className="flex flex-col gap-6">
      <h1 className="text-2xl font-bold tracking-tight lg:text-3xl">{t("ButtonPlaylists")}</h1>
      <QueryState query={playlists}>
        {(data) =>
          data.length === 0 ? (
            <EmptyState title={t("MessageNoUserPlaylists")} />
          ) : (
            <CardGrid shape="square" label={t("ButtonPlaylists")}>
              {data.map((playlist) => {
                const first = playlist.items.find((item) => item.libraryItem)?.libraryItem;
                return (
                  <li key={playlist.id}>
                    <MediaCard
                      href={`/playlist/${playlist.id}`}
                      title={playlist.name}
                      subtitle={t("WebItemsCount", playlist.items.length)}
                      cover={first ? coverUrl(client, first) : null}
                      shape={shape === "book" ? "square" : shape}
                      badge={String(playlist.items.length)}
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

export function PlaylistDetail({ playlistId }: { playlistId: string }) {
  const { t } = useI18n();
  const { client } = useAbs();
  const router = useRouter();
  const playlist = usePlaylist(playlistId);
  useLibrary(playlist.data?.libraryId);
  const remove = useRemoveFromPlaylist();
  const deletePlaylist = useDeletePlaylist();
  return (
    <QueryState query={playlist}>
      {(data) => {
        const leave = () => router.replace(`/library/${data.libraryId}/playlists`);
        return (
          <ListDetail
            name={data.name}
            description={data.description}
            label={t("HeaderPlaylistItems")}
            entries={playlistEntries(client, data.items)}
            remove={{
              label: (title) => t("WebRemoveNamedFromPlaylist", title),
              run: (entry) =>
                remove.mutate(
                  { playlistId, entry },
                  // The server deletes a playlist once its last entry is removed.
                  { onSuccess: (updated) => (updated.items.length ? undefined : leave()) },
                ),
            }}
            deletion={{
              label: t("WebDeletePlaylist"),
              run: () => deletePlaylist.mutate(playlistId, { onSuccess: leave }),
            }}
            busy={remove.isPending || deletePlaylist.isPending}
            error={remove.error ?? deletePlaylist.error}
          />
        );
      }}
    </QueryState>
  );
}
