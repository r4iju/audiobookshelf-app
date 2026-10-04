import { boundary } from "@/server/http";
import { callbackOpenId } from "@/server/openid";
export const runtime = "nodejs";
export const dynamic = "force-dynamic";
export function GET(request: Request) {
  return boundary(() => callbackOpenId(request));
}
