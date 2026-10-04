import { z } from "zod";
import { LibrarySearch } from "@/components/library/search";
import { MAX_SEARCH_RESULTS } from "@/lib/abs/search-limits";
import { toSearchParams } from "@/lib/search-params";

/** The server's own default; asking for more is how a search shows the rest, since it has no paging. */
const FIRST_RESULTS = 12;
const limitSchema = z.coerce
  .number()
  .int()
  .min(FIRST_RESULTS)
  .transform((limit) => Math.min(limit, MAX_SEARCH_RESULTS))
  .catch(FIRST_RESULTS);

export default async function SearchPage({
  params,
  searchParams,
}: {
  params: Promise<{ libraryId: string }>;
  searchParams: Promise<Record<string, string | string[] | undefined>>;
}) {
  const [{ libraryId }, record] = await Promise.all([params, searchParams]);
  const query = toSearchParams(record);
  return (
    <LibrarySearch
      libraryId={libraryId}
      q={query.get("q") ?? ""}
      limit={limitSchema.parse(query.get("limit"))}
    />
  );
}
