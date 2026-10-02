import { SeriesDetail } from "@/components/library/series";

export default async function SeriesPage({
  params,
}: {
  params: Promise<{ libraryId: string; seriesId: string }>;
}) {
  const { libraryId, seriesId } = await params;
  return <SeriesDetail libraryId={libraryId} seriesId={seriesId} />;
}
