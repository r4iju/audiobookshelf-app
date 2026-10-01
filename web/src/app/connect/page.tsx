import type { Metadata } from "next";
import { ConnectScreen } from "@/components/connect/connect-screen";

export const metadata: Metadata = { title: "Connect" };

export default async function ConnectPage({
  searchParams,
}: {
  searchParams: Promise<{ server?: string; username?: string }>;
}) {
  const { server, username } = await searchParams;
  return <ConnectScreen initialServer={server ?? ""} initialUsername={username ?? ""} />;
}
