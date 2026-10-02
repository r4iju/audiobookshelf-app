import { Reader } from "@/components/reader/reader";
import { toSearchParams } from "@/lib/search-params";

export default async function ReadPage({
  params,
  searchParams,
}: {
  params: Promise<{ itemId: string }>;
  searchParams: Promise<Record<string, string | string[] | undefined>>;
}) {
  const [{ itemId }, record] = await Promise.all([params, searchParams]);
  return <Reader itemId={itemId} fileIno={toSearchParams(record).get("file")} />;
}
