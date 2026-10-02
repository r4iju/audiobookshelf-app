import { EpisodeDetail } from "@/components/item/episode-detail";

export default async function EpisodePage({
  params,
}: {
  params: Promise<{ itemId: string; episodeId: string }>;
}) {
  const { itemId, episodeId } = await params;
  return <EpisodeDetail itemId={itemId} episodeId={episodeId} />;
}
