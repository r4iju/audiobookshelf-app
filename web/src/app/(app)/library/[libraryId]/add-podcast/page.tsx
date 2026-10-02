import { AddPodcast } from "@/components/library/add-podcast";
import { toSearchParams } from "@/lib/search-params";

export default async function AddPodcastPage({
  params,
  searchParams,
}: {
  params: Promise<{ libraryId: string }>;
  searchParams: Promise<Record<string, string | string[] | undefined>>;
}) {
  const [{ libraryId }, record] = await Promise.all([params, searchParams]);
  const query = toSearchParams(record);
  return <AddPodcast libraryId={libraryId} q={query.get("q") ?? ""} feed={query.get("feed") ?? ""} />;
}
