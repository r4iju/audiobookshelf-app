import "server-only";
import { randomUUID } from "node:crypto";
import { z } from "zod";
import type { deliveryImportInput } from "@/lib/abs/imports";
import { type Account, DomainError, findAccount } from "./accounts";
import { itemFor } from "./catalog";
import { catalogChanged, database, transaction } from "./data";
import { devicesInput, saveSmtpSettings, smtpInput } from "./delivery";
import { feedRecord, saveImportedFeed, validateFeedAddress } from "./feeds";
import { readArchive, seal } from "./secrets";

export { deliveryImportInput } from "@/lib/abs/imports";

const rowSchema = z.record(z.string(), z.union([z.string(), z.number().finite(), z.null()]));
const identifier = z.string().min(1).max(256);
function owner(actor: Account) {
  if (!actor.active || actor.type !== "root") throw new DomainError(403, "Owner access required");
}
function inventory(actor: Account, input: z.infer<typeof deliveryImportInput>) {
  owner(actor);
  const db = database(),
    base = validateFeedAddress(input.serverAddress);
  if (!db.prepare("SELECT id FROM migrations WHERE digest=? AND scope='media'").get(input.digest))
    throw new DomainError(409, "Complete the same snapshot's media import first");
  const rows = (table: string) =>
    db
      .prepare("SELECT content FROM migration_archive WHERE digest=? AND table_name=? ORDER BY row_key")
      .all(input.digest, table)
      .map((r) => rowSchema.parse(readArchive(z.string().parse(r.content))));
  const errors: { table: string; id: string; message: string }[] = [],
    unsupported: { table: string; id: string; fields: string[] }[] = [];
  const feeds: z.infer<typeof feedRecord>[] = [],
    episodes = rows("feedEpisodes"),
    consumed = new Set<string>();
  const originals = rows("libraryItems");
  for (const row of rows("feeds")) {
    try {
      const id = identifier.parse(row.id),
        itemId = identifier.parse(row.entityId),
        ownerId = identifier.parse(row.userId);
      if (row.entityType !== "libraryItem") throw new Error("Unsupported feed entity type");
      const publisher = findAccount(ownerId),
        item = itemFor(publisher, itemId);
      if (!["root", "admin"].includes(publisher.type) || !publisher.active)
        throw new Error("Original feed publisher is not an active administrator");
      if (
        db
          .prepare("SELECT id FROM rss_feeds WHERE id=? OR slug=? OR item_id=?")
          .get(id, z.string().parse(row.slug), itemId)
      )
        throw new Error("Destination feed identity, slug or item already exists");
      const slug = z
        .string()
        .regex(/^[a-z0-9][a-z0-9_-]{0,127}$/)
        .parse(row.slug);
      const original = originals.find((r) => r.id === itemId);
      if (!original) throw new Error("Original library item is missing");
      const originalFiles = z
        .array(z.object({ ino: z.union([z.string(), z.number()]), metadata: z.object({ path: z.string() }) }))
        .parse(JSON.parse(z.string().parse(original.libraryFiles)));
      const associations = episodes
        .filter((e) => e.feedId === id)
        .map((e) => {
          const episodeId = identifier.parse(e.id),
            originalFile = originalFiles.find((f) => f.metadata.path === e.filePath);
          const file = item.libraryFiles?.find(
            (f) => f.ino === String(originalFile?.ino) && f.fileType === "audio",
          );
          if (!file) throw new Error("Original feed episode cannot be mapped to a downloaded audio file");
          let path = `/feed/${slug}/item/${encodeURIComponent(episodeId)}/media.${file.metadata.ext.replace(/^\./, "")}`;
          if (e.enclosureURL) {
            path = new URL(z.string().parse(e.enclosureURL)).pathname;
            const oldPrefix = new URL(z.string().parse(row.serverAddress)).pathname.replace(/\/$/, "");
            if (oldPrefix && path.startsWith(`${oldPrefix}/`)) path = path.slice(oldPrefix.length);
          }
          if (!new RegExp(`^/feed/${slug}/item/[^/]+/media\\.[a-z0-9]+$`).test(path))
            throw new Error("Unsupported original enclosure URL");
          const publishedAt = Date.parse(z.string().parse(e.pubDate));
          if (!Number.isFinite(publishedAt)) throw new Error("Invalid original feed episode date");
          return {
            id: episodeId,
            fileId: file.ino,
            path,
            title: z.string().max(4096).parse(e.title),
            description: z
              .string()
              .max(65536)
              .parse(e.description ?? ""),
            publishedAt,
            duration: z
              .number()
              .nonnegative()
              .parse(e.duration ?? 0),
          };
        });
      if (
        !associations.length ||
        associations.length > 5000 ||
        new Set(associations.map((e) => e.fileId)).size !== associations.length ||
        new Set(associations.map((e) => e.path)).size !== associations.length
      )
        throw new Error("Feed requires 1–5000 uniquely mapped audio episodes");
      const feed = feedRecord.parse({
        id,
        itemId,
        ownerId,
        slug,
        base,
        episodes: associations,
        meta: {
          title: z.string().max(4096).parse(row.title),
          preventIndexing: row.preventIndexing === 1,
          ownerName: z
            .string()
            .max(256)
            .parse(row.ownerName ?? ""),
          ownerEmail: z.union([z.email(), z.literal("")]).parse(row.ownerEmail ?? ""),
        },
      });
      feeds.push(feed);
      for (const e of associations) consumed.add(e.id);
    } catch (error) {
      errors.push({
        table: "feeds",
        id: String(row.id),
        message: error instanceof Error ? error.message : "Invalid feed",
      });
    }
  }
  for (const e of episodes)
    if (!consumed.has(String(e.id)))
      errors.push({ table: "feedEpisodes", id: String(e.id), message: "Unmapped original feed episode" });
  let smtp: z.infer<typeof smtpInput> | undefined, devices: z.infer<typeof devicesInput> | undefined;
  for (const row of rows("settings")) {
    let value: Record<string, unknown>;
    try {
      value = z.record(z.string(), z.unknown()).parse(JSON.parse(z.string().parse(row.value)));
    } catch {
      errors.push({ table: "settings", id: String(row.id), message: "Invalid original setting JSON" });
      continue;
    }
    if (row.id !== "email-settings" && value.id !== "email-settings") continue;
    try {
      if (smtp || devices) throw new Error("Duplicate email settings");
      if (value.rejectUnauthorized === false)
        throw new Error("Unverified SMTP TLS requires a trusted configuration before migration");
      if (value.host)
        smtp = smtpInput.parse({
          host: value.host,
          port: value.port,
          secure: value.secure,
          fromAddress: value.fromAddress,
          username: value.user ?? "",
          password: value.pass ?? "",
        });
      devices = devicesInput.parse({ ereaderDevices: value.ereaderDevices ?? [] });
      if (new Set(devices.ereaderDevices.map((d) => d.name)).size !== devices.ereaderDevices.length)
        throw new Error("Duplicate original device names");
      for (const d of devices.ereaderDevices) for (const id of d.users) findAccount(id);
      const fields = Object.keys(value).filter(
        (k) =>
          ![
            "id",
            "host",
            "port",
            "secure",
            "rejectUnauthorized",
            "user",
            "pass",
            "fromAddress",
            "ereaderDevices",
          ].includes(k),
      );
      if (fields.length) unsupported.push({ table: "settings", id: String(row.id), fields });
    } catch {
      errors.push({
        table: "settings",
        id: String(row.id),
        message: "Original SMTP or device configuration requires resolution",
      });
    }
  }
  for (const [table, known] of [
    [
      "feeds",
      [
        "id",
        "slug",
        "entityType",
        "entityId",
        "userId",
        "serverAddress",
        "title",
        "ownerName",
        "ownerEmail",
        "preventIndexing",
      ],
    ],
    [
      "feedEpisodes",
      [
        "id",
        "feedId",
        "title",
        "filePath",
        "enclosureURL",
        "enclosureType",
        "enclosureSize",
        "pubDate",
        "duration",
        "description",
      ],
    ],
  ] as const)
    for (const r of rows(table)) {
      const fields = Object.keys(r).filter((k) => !(known as readonly string[]).includes(k));
      if (fields.length) unsupported.push({ table, id: String(r.id), fields });
    }
  if (smtp && db.prepare("SELECT key FROM product_settings WHERE key='smtp'").get())
    errors.push({
      table: "settings",
      id: "email-settings",
      message: "Destination SMTP settings already exist",
    });
  if (devices && db.prepare("SELECT key FROM product_settings WHERE key='ereaders'").get())
    errors.push({
      table: "settings",
      id: "email-settings",
      message: "Destination e-reader settings already exist",
    });
  return {
    feeds,
    smtp,
    devices,
    report: {
      digest: input.digest,
      scope: "delivery",
      canImport: errors.length === 0,
      canCutover: false,
      counts: {
        feeds: feeds.length,
        episodes: consumed.size,
        devices: devices?.ereaderDevices.length ?? 0,
        smtp: smtp ? 1 : 0,
      },
      errors,
      unsupported,
      notices: [
        "Feed addresses use the explicitly selected replacement server URL. Original feed IDs, slugs, episode GUIDs and enclosure paths are retained.",
        "Unmapped configuration fields remain in the private archive and must be resolved before full cutover.",
      ],
    },
  };
}
export function inspectDelivery(actor: Account, input: z.infer<typeof deliveryImportInput>) {
  return inventory(actor, input).report;
}
export function importDelivery(actor: Account, input: z.infer<typeof deliveryImportInput>) {
  owner(actor);
  const prior = database()
    .prepare("SELECT content FROM migrations WHERE digest=? AND scope='delivery'")
    .get(input.digest);
  if (prior) {
    const value = JSON.parse(z.string().parse(prior.content));
    if (value.serverAddress !== validateFeedAddress(input.serverAddress))
      throw new DomainError(409, "Delivery import already used a different server address");
    return value;
  }
  const loaded = inventory(actor, input);
  if (!loaded.report.canImport)
    throw new DomainError(409, "Resolve original feed and delivery errors before import");
  const result = transaction((db) => {
    owner(actor);
    for (const feed of loaded.feeds) saveImportedFeed(feed);
    if (loaded.smtp) saveSmtpSettings(actor, loaded.smtp);
    if (loaded.devices)
      db.prepare("INSERT INTO product_settings VALUES('ereaders',?)").run(seal(loaded.devices));
    const value = {
      id: randomUUID(),
      digest: input.digest,
      scope: "delivery",
      serverAddress: validateFeedAddress(input.serverAddress),
      accountCount: new Set(loaded.feeds.map((f) => f.ownerId)).size,
      completedAt: Date.now(),
      report: loaded.report,
    };
    db.prepare("INSERT INTO migrations VALUES(?,?,?,?)").run(
      value.id,
      input.digest,
      "delivery",
      JSON.stringify(value),
    );
    return value;
  });
  catalogChanged();
  return result;
}
