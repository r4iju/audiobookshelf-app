import { type PendingOpenId, pendingOpenIdSchema } from "@/lib/abs/auth";

// sessionStorage keeps the PKCE verifier to this tab and drops it when the tab closes.
const KEY = "abs-web:v1:openid-pending";

export function savePendingOpenId(pending: PendingOpenId) {
  sessionStorage.setItem(KEY, JSON.stringify(pending));
}

export function takePendingOpenId(): PendingOpenId | null {
  const raw = sessionStorage.getItem(KEY);
  sessionStorage.removeItem(KEY);
  if (!raw) return null;
  try {
    const parsed = pendingOpenIdSchema.safeParse(JSON.parse(raw));
    return parsed.success ? parsed.data : null;
  } catch {
    return null;
  }
}
