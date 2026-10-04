import type { Metadata } from "next";
import { SetupScreen } from "@/components/setup/setup-screen";
import { initialized } from "@/server/data";

export const metadata: Metadata = { title: "Set up Leafwake" };
export const dynamic = "force-dynamic";
export default function SetupPage() {
  return <SetupScreen ready={initialized()} />;
}
