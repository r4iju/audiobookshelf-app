import { z } from "zod";
import { LatestEpisodes } from "@/components/library/latest";
import { toSearchParams } from "@/lib/search-params";

const pageSchema = z.coerce.number().int().positive().catch(1);

export default async function LatestEpisodesPage({
  params,
  searchParams,
}: {
  params: Promise<{ libraryId: string }>;
  searchParams: Promise<Record<string, string | string[] | undefined>>;
}) {
  const [{ libraryId }, record] = await Promise.all([params, searchParams]);
  return <LatestEpisodes libraryId={libraryId} page={pageSchema.parse(toSearchParams(record).get("page"))} />;
}
