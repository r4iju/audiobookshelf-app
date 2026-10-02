import { AuthorsList } from "@/components/library/authors";

export default async function AuthorsPage({ params }: { params: Promise<{ libraryId: string }> }) {
  const { libraryId } = await params;
  return <AuthorsList libraryId={libraryId} />;
}
