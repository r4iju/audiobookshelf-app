import { redirect } from "next/navigation";
import { RootRedirect } from "@/components/app/root-redirect";
import { initialized } from "@/server/data";

export const dynamic = "force-dynamic";

export default function Home() {
  if (!initialized()) redirect("/setup");
  return <RootRedirect />;
}
