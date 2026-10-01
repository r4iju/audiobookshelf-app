import { LibrarySearch } from "@/components/library/search";

export default async function SearchPage({
  params,
  searchParams,
}: {
  params: Promise<{ libraryId: string }>;
  searchParams: Promise<{ q?: string | string[] }>;
}) {
  const { libraryId } = await params;
  const { q } = await searchParams;
  return <LibrarySearch libraryId={libraryId} q={(Array.isArray(q) ? q[0] : q) ?? ""} />;
}
