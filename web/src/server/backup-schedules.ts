import "server-only";
import { randomUUID } from "node:crypto";
import { readdirSync, readFileSync, rmSync } from "node:fs";
import { resolve } from "node:path";
import { z } from "zod";
import { backupConfigurationSchema } from "@/lib/abs/backup-settings";
import { backupManifestSchema } from "../../backup-format.mjs";
import { type Account, DomainError, findAccount } from "./accounts";
import { createBackup } from "./backups";
import { database, dataDirectory, transaction } from "./data";

const configurationDefault = { enabled: false, intervalMinutes: 1440, keepLast: 7 };
const stateSchema = z.object({
  nextAt: z.number().nullable(),
  pendingId: z.string().uuid().nullable(),
  leaseUntil: z.number().nullable(),
  lastCompletedAt: z.number().nullable(),
  lastError: z.string().nullable(),
});
const stateDefault = {
  nextAt: null,
  pendingId: null,
  leaseUntil: null,
  lastCompletedAt: null,
  lastError: null,
};
function owner(actor: Account) {
  const current = findAccount(actor.id);
  if (!current.active) throw new DomainError(401, "Sign-in required");
  if (current.type !== "root") throw new DomainError(403, "Owner access required");
  return current;
}
function read(key: string) {
  const row = database().prepare("SELECT content FROM product_settings WHERE key=?").get(key);
  return row ? JSON.parse(String(row.content)) : undefined;
}
function configuration() {
  return backupConfigurationSchema.parse(read("backup_configuration") ?? configurationDefault);
}
function state() {
  return stateSchema.parse(read("backup_schedule") ?? stateDefault);
}
function write(key: string, value: unknown) {
  database()
    .prepare(
      "INSERT INTO product_settings VALUES(?,?) ON CONFLICT(key) DO UPDATE SET content=excluded.content",
    )
    .run(key, JSON.stringify(value));
}
export function backupSettings(actor: Account) {
  owner(actor);
  const current = state();
  return {
    configuration: configuration(),
    schedule: {
      nextAt: current.nextAt,
      lastCompletedAt: current.lastCompletedAt,
      lastError: current.lastError,
    },
  };
}
export function updateBackupSettings(actor: Account, input: z.infer<typeof backupConfigurationSchema>) {
  owner(actor);
  transaction(() => {
    const previous = configuration();
    write("backup_configuration", input);
    if (previous.enabled !== input.enabled || previous.intervalMinutes !== input.intervalMinutes)
      write("backup_schedule", {
        ...state(),
        pendingId: null,
        leaseUntil: null,
        nextAt: input.enabled ? Date.now() + input.intervalMinutes * 60000 : null,
      });
  });
  return backupSettings(actor);
}
function prune(keepLast: number) {
  const folder = resolve(dataDirectory(), "backups");
  const scheduled = readdirSync(folder)
    .filter((name) => /^[a-f0-9-]{36}\.json$/.test(name))
    .flatMap((name) => {
      try {
        const manifest = backupManifestSchema.parse(JSON.parse(readFileSync(resolve(folder, name), "utf8")));
        return manifest.scheduled && `${manifest.id}.json` === name ? [manifest] : [];
      } catch {
        return [];
      }
    })
    .sort((a, b) => b.createdAt - a.createdAt);
  for (const manifest of scheduled.slice(keepLast))
    for (const extension of ["json", "sqlite", "key"])
      rmSync(resolve(folder, `${manifest.id}.${extension}`), { force: true });
}
declare global {
  var leafwakeBackupSchedule: { running: boolean; timer: ReturnType<typeof setInterval> } | undefined;
}
export function startBackupSchedules() {
  if (globalThis.leafwakeBackupSchedule) return;
  const timer = setInterval(() => {
    void tick().catch(() => {});
  }, 60_000);
  timer.unref();
  globalThis.leafwakeBackupSchedule = { running: false, timer };
  void tick().catch(() => {});
}
async function tick() {
  const worker = globalThis.leafwakeBackupSchedule,
    settings = configuration(),
    current = state(),
    now = Date.now();
  if (
    !worker ||
    worker.running ||
    !settings.enabled ||
    current.nextAt == null ||
    current.nextAt > now ||
    (current.leaseUntil ?? 0) > now ||
    globalThis.leafwakeMaintenance
  )
    return;
  const row = database().prepare("SELECT id FROM users WHERE type='root' AND active=1").get();
  if (!row) return;
  worker.running = true;
  const id = current.pendingId ?? randomUUID();
  transaction(() => write("backup_schedule", { ...current, pendingId: id, leaseUntil: now + 120000 }));
  try {
    const actor = findAccount(String(row.id));
    await createBackup(
      actor,
      () => {
        if (!configuration().enabled) throw new DomainError(409, "Scheduled backups were disabled");
        return owner(actor);
      },
      id,
    );
    prune(configuration().keepLast);
    transaction(() => {
      const latest = state();
      if (latest.pendingId === id)
        write("backup_schedule", {
          ...latest,
          pendingId: null,
          leaseUntil: null,
          nextAt: Date.now() + configuration().intervalMinutes * 60000,
          lastCompletedAt: Date.now(),
          lastError: null,
        });
    });
  } catch {
    transaction(() => {
      const latest = state();
      if (latest.pendingId === id)
        write("backup_schedule", {
          ...latest,
          leaseUntil: null,
          nextAt: Date.now() + 60000,
          lastError:
            "Scheduled backup failed. Check data storage, free space and backup integrity in diagnostics.",
        });
    });
  } finally {
    worker.running = false;
  }
}
