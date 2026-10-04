import "server-only";
import { lookup } from "node:dns/promises";
import { request as httpRequest, type IncomingMessage } from "node:http";
import { request as httpsRequest } from "node:https";
import { BlockList, isIP } from "node:net";
import { DomainError } from "./accounts";

const denied = new BlockList();
for (const [network, prefix] of [
  ["0.0.0.0", 8],
  ["10.0.0.0", 8],
  ["127.0.0.0", 8],
  ["169.254.0.0", 16],
  ["172.16.0.0", 12],
  ["192.168.0.0", 16],
  ["100.64.0.0", 10],
  ["192.0.0.0", 24],
  ["192.0.2.0", 24],
  ["198.18.0.0", 15],
  ["198.51.100.0", 24],
  ["203.0.113.0", 24],
  ["224.0.0.0", 4],
  ["240.0.0.0", 4],
] as const)
  denied.addSubnet(network, prefix, "ipv4");
const globalV6 = new BlockList();
globalV6.addSubnet("2000::", 3, "ipv6");
denied.addSubnet("2001:db8::", 32, "ipv6");
function allowed(address: string) {
  const family = isIP(address);
  if (family === 4) return !denied.check(address, "ipv4");
  return family === 6 && globalV6.check(address, "ipv6") && !denied.check(address, "ipv6");
}
export function remoteUrl(value: string) {
  let url: URL;
  try {
    url = new URL(value);
  } catch {
    throw new DomainError(400, "Invalid feed or enclosure URL");
  }
  if (
    !["http:", "https:"].includes(url.protocol) ||
    url.username ||
    url.password ||
    url.hash ||
    value.length > 4096
  )
    throw new DomainError(400, "Only unauthenticated HTTP(S) feed URLs are supported");
  return url;
}
export async function remoteAddress(host: string, signal: AbortSignal, allowedHosts: string) {
  const lan = allowedHosts
    .split(",")
    .map((h) => h.trim().toLowerCase())
    .includes(host.toLowerCase());
  const resolved = isIP(host)
    ? [{ address: host, family: isIP(host) }]
    : await new Promise<{ address: string; family: number }[]>((resolve, reject) => {
        const aborted = () => reject(signal.reason ?? new Error("Remote lookup cancelled"));
        if (signal.aborted) return aborted();
        signal.addEventListener("abort", aborted, { once: true });
        lookup(host, { all: true, verbatim: true })
          .then(resolve, reject)
          .finally(() => signal.removeEventListener("abort", aborted));
      });
  signal.throwIfAborted();
  if (!resolved.length || (!lan && resolved.some((entry) => !allowed(entry.address))))
    throw new DomainError(400, "Private feed hosts require explicit server configuration");
  const selected = resolved[0];
  if (!selected) throw new DomainError(400, "Feed host is unavailable");
  return selected;
}
export async function remoteStream(
  value: string,
  maxBytes: number,
  signal: AbortSignal,
  redirects = 0,
  options: {
    method?: string;
    headers?: Record<string, string>;
    body?: string;
    allowedHosts?: string;
    rawStatus?: boolean;
  } = {},
): Promise<IncomingMessage> {
  const url = remoteUrl(value),
    host = url.hostname.replace(/^\[|\]$/g, "");
  const selected = await remoteAddress(
    host,
    signal,
    options.allowedHosts ?? process.env.LEAFWAKE_FEED_ALLOWED_HOSTS ?? "",
  );
  const response = await new Promise<IncomingMessage>((resolve, reject) => {
    const request = (url.protocol === "https:" ? httpsRequest : httpRequest)(
      url,
      {
        signal,
        agent: false,
        family: selected.family,
        lookup: (_host, options, callback) =>
          callback(null, options.all ? [selected] : selected.address, selected.family),
        method: options.method ?? "GET",
        headers: { ...options.headers, "user-agent": "Leafwake/1.0", "accept-encoding": "identity" },
        timeout: 20000,
      },
      resolve,
    );
    request.once("error", reject);
    request.once("timeout", () => request.destroy(new Error("Remote request timed out")));
    request.end(options.body);
  });
  if (!options.rawStatus && [301, 302, 303, 307, 308].includes(response.statusCode ?? 0)) {
    const location = response.headers.location;
    response.destroy();
    if (!location || redirects >= 5) throw new DomainError(400, "Feed redirect limit exceeded");
    return remoteStream(new URL(location, url).toString(), maxBytes, signal, redirects + 1, options);
  }
  if (!options.rawStatus && response.statusCode !== 200) {
    response.destroy();
    throw new DomainError(400, `Remote server returned ${response.statusCode ?? 0}`);
  }
  if (response.headers["content-encoding"] && response.headers["content-encoding"] !== "identity") {
    response.destroy();
    throw new DomainError(400, "Compressed remote responses are not supported");
  }
  const size = Number(response.headers["content-length"]);
  if (Number.isFinite(size) && size > maxBytes) {
    response.destroy();
    throw new DomainError(400, "Remote file exceeds the size limit");
  }
  return response;
}
export async function remoteText(value: string) {
  const response = await remoteStream(value, 2 * 1024 * 1024, AbortSignal.timeout(20000));
  const chunks: Buffer[] = [];
  let size = 0;
  for await (const chunk of response) {
    const bytes = Buffer.isBuffer(chunk) ? chunk : Buffer.from(chunk);
    size += bytes.length;
    if (size > 2 * 1024 * 1024) {
      response.destroy();
      throw new DomainError(400, "Feed exceeds the size limit");
    }
    chunks.push(bytes);
  }
  return Buffer.concat(chunks).toString("utf8");
}
