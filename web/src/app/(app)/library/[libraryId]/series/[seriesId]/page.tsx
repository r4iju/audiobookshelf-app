import { SeriesDetail } from "@/components/library/series";

export default async function SeriesPage({
  params,
  searchParams,
}: {
  params: Promise<{ libraryId: string; seriesId: string }>;
  searchParams: Promise<{ page?: string | string[] }>;
}) {
  const { libraryId, seriesId } = await params;
  const page = Number((await searchParams).page);
  return (
    <SeriesDetail
      libraryId={libraryId}
      seriesId={decodeURIComponent(seriesId)}
      page={Number.isInteger(page) && page > 0 ? page : 1}
    />
  );
}
