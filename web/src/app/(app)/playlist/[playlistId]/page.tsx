import { PlaylistDetail } from "@/components/lists/playlists";

export default async function PlaylistPage({ params }: { params: Promise<{ playlistId: string }> }) {
  const { playlistId } = await params;
  return <PlaylistDetail playlistId={playlistId} />;
}
