import { PlaylistList } from "@/components/lists/playlists";

export default async function PlaylistsPage({ params }: { params: Promise<{ libraryId: string }> }) {
  const { libraryId } = await params;
  return <PlaylistList libraryId={libraryId} />;
}
