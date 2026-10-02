import { CollectionDetail } from "@/components/lists/collections";

export default async function CollectionPage({ params }: { params: Promise<{ collectionId: string }> }) {
  const { collectionId } = await params;
  return <CollectionDetail collectionId={collectionId} />;
}
