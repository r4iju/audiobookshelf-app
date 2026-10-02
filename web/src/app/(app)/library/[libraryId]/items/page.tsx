import { LibraryBrowse } from "@/components/library/browse";
import { browseFromParams } from "@/lib/abs/browse";
import { toSearchParams } from "@/lib/search-params";

export default async function LibraryItemsPage({
  params,
  searchParams,
}: {
  params: Promise<{ libraryId: string }>;
  searchParams: Promise<Record<string, string | string[] | undefined>>;
}) {
  const { libraryId } = await params;
  return <LibraryBrowse libraryId={libraryId} state={browseFromParams(toSearchParams(await searchParams))} />;
}
