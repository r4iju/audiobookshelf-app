import { DomainError } from "@/server/accounts";
import { publicFeed } from "@/server/feeds";
import { boundary } from "@/server/http";
export const runtime = "nodejs";
export const dynamic = "force-dynamic";
export function GET(request: Request) {
  return boundary(() => {
    const path = new URL(request.url).pathname.slice((globalThis.leafwakeBasePath || "").length),
      legacy = path.match(/^\/feed\/([a-z0-9][a-z0-9_-]{0,127})\/item\/[^/]+\/media\.[a-z0-9]+$/);
    if (legacy?.[1]) return publicFeed(request, legacy[1], undefined, path);
    const match = path.match(/^\/feed\/([a-z0-9][a-z0-9_-]{0,127})(?:\/media\/([^/]+))?$/);
    if (!match?.[1]) throw new DomainError(404, "Not found");
    return publicFeed(request, match[1], match[2] ? decodeURIComponent(match[2]) : undefined);
  });
}
export const HEAD = GET;
