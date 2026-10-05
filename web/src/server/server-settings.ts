import "server-only";
import { z } from "zod";
import { type Account, requireAdministrator } from "./accounts";
import { database, transaction } from "./data";

const origin = z
  .string()
  .max(2048)
  .refine((value) => {
    try {
      const url = new URL(value);
      return ["http:", "https:"].includes(url.protocol) && value === url.origin;
    } catch {
      return false;
    }
  }, "Use an exact HTTP(S) origin");
export const serverSettingsSchema = z.object({
  serverName: z.string().trim().min(1).max(256),
  language: z.string().regex(/^[a-z]{2}(?:-[A-Za-z]{2})?$/),
  loginMessage: z.string().max(4096),
  allowedOrigins: z.array(origin).max(32),
  rateLimitLoginRequests: z.number().int().min(1).max(50),
  rateLimitLoginWindow: z.number().int().min(60000).max(3600000),
  maxScanEntries: z.number().int().min(100).max(20000),
  maxScanDepth: z.number().int().min(1).max(32),
  maxMediaProbes: z.number().int().min(1).max(4),
});
const defaults = {
  serverName: "Audiobook Loft",
  language: "en",
  loginMessage: "",
  allowedOrigins: [],
  rateLimitLoginRequests: 12,
  rateLimitLoginWindow: 300000,
  maxScanEntries: 20000,
  maxScanDepth: 32,
  maxMediaProbes: 4,
};
export function serverSettings() {
  const row = database().prepare("SELECT content FROM product_settings WHERE key='server'").get();
  return serverSettingsSchema.parse(row ? JSON.parse(z.string().parse(row.content)) : defaults);
}
export function saveServerSettings(actor: Account, settings: z.infer<typeof serverSettingsSchema>) {
  requireAdministrator(actor);
  transaction((db) => {
    const previous = serverSettings();
    db.prepare(
      "INSERT INTO product_settings VALUES('server',?) ON CONFLICT(key) DO UPDATE SET content=excluded.content",
    ).run(JSON.stringify(settings));
    // A changed window starts new buckets rather than retaining expiry under the old policy.
    if (previous.rateLimitLoginWindow !== settings.rateLimitLoginWindow)
      db.prepare("DELETE FROM login_attempts").run();
  });
  return settings;
}
export function originAllowed(value: string, host: string) {
  try {
    const url = new URL(value);
    return (
      ["http:", "https:"].includes(url.protocol) &&
      value === url.origin &&
      (url.host === host || serverSettings().allowedOrigins.includes(value))
    );
  } catch {
    return false;
  }
}
declare global {
  var leafwakeOriginAllowed: ((origin: string, host: string) => boolean) | undefined;
}
globalThis.leafwakeOriginAllowed = originAllowed;
