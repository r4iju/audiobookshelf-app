import "server-only";
import { createCipheriv, createDecipheriv, hkdfSync, randomBytes } from "node:crypto";
import { tokenSigningKey } from "./data";

function key() {
  return Buffer.from(hkdfSync("sha256", tokenSigningKey(), "Leafwake", "private-settings-v1", 32));
}
export function seal(value: unknown) {
  const iv = randomBytes(12),
    cipher = createCipheriv("aes-256-gcm", key(), iv);
  const bytes = Buffer.concat([cipher.update(JSON.stringify(value), "utf8"), cipher.final()]);
  return JSON.stringify({
    iv: iv.toString("base64"),
    tag: cipher.getAuthTag().toString("base64"),
    bytes: bytes.toString("base64"),
  });
}
export function unseal(value: string): unknown {
  const box = JSON.parse(value),
    decipher = createDecipheriv("aes-256-gcm", key(), Buffer.from(box.iv, "base64"));
  decipher.setAuthTag(Buffer.from(box.tag, "base64"));
  return JSON.parse(
    Buffer.concat([decipher.update(Buffer.from(box.bytes, "base64")), decipher.final()]).toString("utf8"),
  );
}
