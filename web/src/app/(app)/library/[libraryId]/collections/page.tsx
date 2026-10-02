import { CollectionList } from "@/components/lists/collections";

export default async function CollectionsPage({ params }: { params: Promise<{ libraryId: string }> }) {
  const { libraryId } = await params;
  return <CollectionList libraryId={libraryId} />;
}
