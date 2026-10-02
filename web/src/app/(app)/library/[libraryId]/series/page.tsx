import { SeriesList } from "@/components/library/series";

export default async function SeriesListPage({
  params,
  searchParams,
}: {
  params: Promise<{ libraryId: string }>;
  searchParams: Promise<{ page?: string | string[] }>;
}) {
  const { libraryId } = await params;
  const page = Number((await searchParams).page);
  return <SeriesList libraryId={libraryId} page={Number.isInteger(page) && page > 0 ? page : 1} />;
}
