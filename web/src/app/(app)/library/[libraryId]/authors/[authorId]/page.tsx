import { AuthorDetail } from "@/components/library/authors";

export default async function AuthorPage({
  params,
}: {
  params: Promise<{ libraryId: string; authorId: string }>;
}) {
  const { libraryId, authorId } = await params;
  return <AuthorDetail libraryId={libraryId} authorId={decodeURIComponent(authorId)} />;
}
