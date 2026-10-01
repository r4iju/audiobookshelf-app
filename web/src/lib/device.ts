import { z } from "zod";
import { readStored, writeStored } from "@/lib/storage/local";

const KEY = "abs-web:v1:device-id";

export const clientVersion = process.env.NEXT_PUBLIC_CLIENT_VERSION ?? "0.1.0";

/** One id per browser profile so the server lists this browser as a single device across sessions. */
export function deviceInfo() {
  let id = readStored(KEY, z.string());
  if (!id) {
    id = crypto.randomUUID();
    writeStored(KEY, id);
  }
  return {
    deviceId: id,
    clientName: "Audiobookshelf Web",
    clientVersion,
    manufacturer: browserName(),
    model: navigator.platform || undefined,
  };
}

function browserName() {
  const agent = navigator.userAgent;
  if (/Edg\//.test(agent)) return "Edge";
  if (/Firefox\//.test(agent)) return "Firefox";
  if (/Chrome\//.test(agent)) return "Chrome";
  if (/Safari\//.test(agent)) return "Safari";
  return "Browser";
}
