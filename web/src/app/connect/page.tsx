import type { Metadata } from "next";
import { ConnectScreen } from "@/components/connect/connect-screen";

export const metadata: Metadata = { title: "Connect" };

export default async function ConnectPage({
  searchParams,
}: {
  searchParams: Promise<{ server?: string; username?: string; next?: string }>;
}) {
  const { server, username, next } = await searchParams;
  return (
    <ConnectScreen
      initialServer={server ?? ""}
      initialUsername={username ?? ""}
      next={safeNext(next)}
      // Read per request, so one image serves any deployment.
      configuredServer={process.env.ABS_WEB_SERVER}
    />
  );
}

function safeNext(next: string | undefined) {
  return next?.startsWith("/") && !next.startsWith("//") && !next.startsWith("/\\") ? next : "/";
}
