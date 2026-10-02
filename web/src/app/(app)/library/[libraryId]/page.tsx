import { LibraryHome } from "@/components/library/home";

export default async function LibraryHomePage({ params }: { params: Promise<{ libraryId: string }> }) {
  const { libraryId } = await params;
  return <LibraryHome libraryId={libraryId} />;
}
