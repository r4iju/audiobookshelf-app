"use client";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import { useActionState } from "react";
import { z } from "zod";
import { Button, ButtonLink } from "@/components/ui/button";
import { TextField } from "@/components/ui/field";
import { Section } from "@/components/ui/section";
import { Alert, EmptyState, Spinner } from "@/components/ui/status";
import { backupConfigurationSchema, backupSettingsSchema } from "@/lib/abs/backup-settings";
import { useAbs } from "@/lib/session/store";
import { DeliveryImportForm } from "./delivery-import-form";
import { ListImportForm } from "./list-import-form";
import { MediaImportForm } from "./media-import-form";

const backupSchema = z.object({
  id: z.string().uuid(),
  createdAt: z.number(),
  bytes: z.number(),
  sha256: z.string(),
  schema: z.string(),
  formatVersion: z.number().optional(),
  keyIncluded: z.boolean().optional(),
  media: z
    .object({ included: z.boolean(), requiredMounts: z.array(z.string()), managedDirectory: z.string() })
    .optional(),
});
const backupsSchema = z.object({ backups: z.array(backupSchema) });
const diagnosticsSchema = z.object({
  ready: z.boolean(),
  issues: z.array(z.string()),
  database: z.object({ integrity: z.string(), schemaVersion: z.number() }),
  storage: z.object({ writable: z.boolean(), freeBytes: z.number(), databaseBytes: z.number() }),
  tools: z.object({
    ffmpeg: z.object({ available: z.boolean(), version: z.string().nullable() }),
    ffprobe: z.object({ available: z.boolean(), version: z.string().nullable() }),
  }),
  mounts: z.array(z.object({ libraryId: z.string(), path: z.string(), readable: z.boolean() })),
  mountsTruncated: z.boolean(),
  recentFailures: z.array(
    z.object({ kind: z.string(), id: z.string(), occurredAt: z.number(), message: z.string() }),
  ),
});
const migrationsSchema = z.object({
  migrations: z.array(
    z.object({
      id: z.string(),
      digest: z.string(),
      scope: z.string(),
      accountCount: z.number(),
      completedAt: z.number(),
    }),
  ),
});
type Result =
  | { kind: "idle" }
  | { kind: "error"; message: string }
  | { kind: "saved"; message: string }
  | { kind: "restored" };
export function MigrationScreen() {
  const { client, connection } = useAbs();
  const backups = useQuery({
    queryKey: [connection.id, "backups"],
    queryFn: ({ signal }) => client.get("/api/admin/backups", backupsSchema, signal),
  });
  const migrations = useQuery({
    queryKey: [connection.id, "migrations"],
    queryFn: ({ signal }) => client.get("/api/admin/migrations", migrationsSchema, signal),
  });
  return (
    <div className="mx-auto flex max-w-3xl flex-col gap-6">
      <h1 className="text-2xl font-bold">Migration and backups</h1>
      <p>
        Account import is the first migration stage. Complete and validate media, progress, lists and
        configuration before replacing your original installation.
      </p>
      <Section title="Import media and listening history">
        <MediaImportForm />
      </Section>
      <Section title="Import original lists">
        <ListImportForm />
      </Section>
      <Section title="Import feeds and ebook delivery">
        <DeliveryImportForm />
      </Section>
      <Section title="Product backups">
        <p className="text-sm text-muted">
          Backups preserve the database, configuration, metadata and private encryption key. Media files,
          including uploads and downloaded podcast episodes, require a separate copy of their mounts and
          managed media directory. Only the owner can create or restore backups. Treat the backup files as
          private credentials.
        </p>
        <BackupScheduleForm />
        <BackupAction />
        {backups.isPending ? (
          <Spinner label="Loading backups" />
        ) : backups.isError ? (
          <Alert>{backups.error.message}</Alert>
        ) : backups.data.backups.length ? (
          <ul className="space-y-4">
            {backups.data.backups.map((backup) => (
              <li key={backup.id} className="space-y-2 border-t border-line pt-4">
                <p>
                  {new Date(backup.createdAt).toLocaleString()} · {Math.ceil(backup.bytes / 1024)} KiB
                </p>
                <code className="break-all text-xs">{backup.id}</code>
                <p className="text-sm text-muted">
                  {backup.keyIncluded
                    ? "Includes the encryption key; media files excluded."
                    : "Earlier database-only backup. Preserve this installation’s key separately."}
                </p>
                {backup.media ? (
                  <details>
                    <summary>Required media mounts</summary>
                    <ul className="break-all text-sm">
                      {[...new Set([...backup.media.requiredMounts, backup.media.managedDirectory])].map(
                        (path) => (
                          <li key={path}>{path}</li>
                        ),
                      )}
                    </ul>
                  </details>
                ) : null}
                <BackupAction backupId={backup.id} />
              </li>
            ))}
          </ul>
        ) : (
          <EmptyState title="No backups yet" />
        )}
      </Section>
      <Section title="Storage and job diagnostics">
        <Diagnostics />
      </Section>
      <Section title="Completed migration stages">
        {migrations.isPending ? (
          <Spinner label="Loading migration records" />
        ) : migrations.isError ? (
          <Alert>{migrations.error.message}</Alert>
        ) : migrations.data.migrations.length ? (
          <ul>
            {migrations.data.migrations.map((migration) => (
              <li key={migration.id}>
                {migration.scope}: {migration.accountCount} accounts ·{" "}
                {new Date(migration.completedAt).toLocaleString()}
              </li>
            ))}
          </ul>
        ) : (
          <EmptyState title="No migration records" />
        )}
      </Section>
    </div>
  );
}
function BackupAction({ backupId }: { backupId?: string }) {
  const { client, connection } = useAbs();
  const queries = useQueryClient();
  const [result, submit, pending] = useActionState<Result, FormData>(
    async (_previous, form) => {
      try {
        if (backupId) {
          if (form.get("confirmation") !== "RESTORE")
            return {
              kind: "error",
              message: "Enter RESTORE to replace this installation’s database with the selected backup.",
            };
          await client.command("POST", `/api/admin/backups/${backupId}/restore`, {});
          await queries.invalidateQueries({ queryKey: [connection.id] });
          return { kind: "restored" };
        }
        await client.send("POST", "/api/admin/backups", {}, backupSchema);
        await queries.invalidateQueries({ queryKey: [connection.id, "backups"] });
        return { kind: "saved", message: "Backup saved in your persistent data folder." };
      } catch (error) {
        return {
          kind: "error",
          message: error instanceof Error ? error.message : "Maintenance could not complete",
        };
      }
    },
    { kind: "idle" },
  );
  if (result.kind === "restored")
    return (
      <div className="space-y-2">
        <p>Backup restored. Sign in again with an account from that backup.</p>
        <ButtonLink href="/connect">Sign in</ButtonLink>
      </div>
    );
  return (
    <form action={submit} className="space-y-3">
      {backupId ? (
        <>
          <p className="text-sm">
            Restoring replaces the current database and signs out all sessions. Create a current backup first
            and wait for scans and media jobs to finish, then enter RESTORE to confirm. For a new
            installation, use the image maintenance CLI with an empty data volume and restore media mounts
            separately.
          </p>
          <TextField name="confirmation" label="Restore confirmation" required autoComplete="off" />
        </>
      ) : null}
      {result.kind === "error" ? (
        <Alert>{result.message}</Alert>
      ) : result.kind === "saved" ? (
        <p role="status">{result.message}</p>
      ) : null}
      <Button type="submit" disabled={pending} variant={backupId ? "secondary" : "primary"}>
        {pending ? "Working…" : backupId ? "Restore this backup" : "Create backup"}
      </Button>
    </form>
  );
}

function Diagnostics() {
  const { client, connection } = useAbs();
  const query = useQuery({
    queryKey: [connection.id, "diagnostics"],
    queryFn: ({ signal }) => client.get("/api/admin/diagnostics", diagnosticsSchema, signal),
  });
  if (query.isPending) return <Spinner label="Checking storage and tools" />;
  if (query.isError) return <Alert>{query.error.message}</Alert>;
  const data = query.data;
  return (
    <div className="space-y-3">
      <p role="status">
        {data.ready ? "Storage and tools are ready." : "Some installation checks need attention."}
      </p>
      {data.issues.map((issue) => (
        <Alert key={issue}>{issue}</Alert>
      ))}
      <dl className="grid grid-cols-1 gap-2 text-sm sm:grid-cols-2">
        <div>
          <dt>Database</dt>
          <dd>
            {data.database.integrity} · schema {data.database.schemaVersion}
          </dd>
        </div>
        <div>
          <dt>Free storage</dt>
          <dd>{Math.floor(data.storage.freeBytes / (1024 * 1024))} MiB</dd>
        </div>
        <div>
          <dt>FFmpeg</dt>
          <dd>{data.tools.ffmpeg.version ?? "Unavailable"}</dd>
        </div>
        <div>
          <dt>FFprobe</dt>
          <dd>{data.tools.ffprobe.version ?? "Unavailable"}</dd>
        </div>
      </dl>
      <details>
        <summary>Media mount checks</summary>
        <ul className="break-all text-sm">
          {data.mounts.map((mount) => (
            <li key={`${mount.libraryId}:${mount.path}`}>
              {mount.readable ? "Available" : "Unavailable"}: {mount.path}
            </li>
          ))}
        </ul>
        {data.mountsTruncated ? (
          <p>
            Only the first100 libraries and ten folders per library are shown. Check the remaining mounts on
            the host.
          </p>
        ) : null}
      </details>
      {data.recentFailures.length ? (
        <ul className="space-y-2 text-sm">
          {data.recentFailures.map((failure) => (
            <li key={`${failure.kind}:${failure.id}`}>
              <p>
                {failure.kind} · {new Date(failure.occurredAt).toLocaleString()}
              </p>
              <p>{failure.message}</p>
              <code className="break-all">{failure.id}</code>
            </li>
          ))}
        </ul>
      ) : (
        <p className="text-sm text-muted">No failed jobs recorded.</p>
      )}
      <Button variant="secondary" onClick={() => query.refetch()} disabled={query.isFetching}>
        Refresh diagnostics
      </Button>
    </div>
  );
}

function BackupScheduleForm() {
  const { client, connection } = useAbs();
  const queries = useQueryClient();
  const query = useQuery({
    queryKey: [connection.id, "backupSettings"],
    queryFn: ({ signal }) => client.get("/api/admin/backups/settings", backupSettingsSchema, signal),
  });
  const [result, submit, pending] = useActionState<Exclude<Result, { kind: "restored" }>, FormData>(
    async (_previous, form) => {
      const input = backupConfigurationSchema.safeParse({
        enabled: form.has("enabled"),
        intervalMinutes: Number(form.get("intervalMinutes")),
        keepLast: Number(form.get("keepLast")),
      });
      if (!input.success)
        return {
          kind: "error",
          message: "Choose an interval of60–43200minutes and retain1–50 scheduled backups.",
        };
      try {
        await client.send("PATCH", "/api/admin/backups/settings", input.data, backupSettingsSchema);
        await queries.invalidateQueries({ queryKey: [connection.id, "backupSettings"] });
        return { kind: "saved", message: "Backup schedule saved." };
      } catch (error) {
        return {
          kind: "error",
          message: error instanceof Error ? error.message : "Backup schedule could not save",
        };
      }
    },
    { kind: "idle" },
  );
  if (query.isPending) return <Spinner label="Loading backup schedule" />;
  if (query.isError) return <Alert>{query.error.message}</Alert>;
  const { configuration, schedule } = query.data;
  return (
    <form
      action={submit}
      className="space-y-3 rounded-lg border border-line p-3"
      key={`${configuration.enabled}:${configuration.intervalMinutes}:${configuration.keepLast}`}
    >
      <label className="flex gap-2">
        <input name="enabled" type="checkbox" defaultChecked={configuration.enabled} />
        Create scheduled backups
      </label>
      <p className="text-sm text-muted">
        Off by default. Scheduled backups retain the private key and exclude media files. Retention removes
        only scheduled backups; manual backups are preserved.
      </p>
      <TextField
        name="intervalMinutes"
        label="Backup interval in minutes"
        type="number"
        min={60}
        max={43200}
        required
        defaultValue={configuration.intervalMinutes}
      />
      <TextField
        name="keepLast"
        label="Scheduled backups to retain"
        type="number"
        min={1}
        max={50}
        required
        defaultValue={configuration.keepLast}
      />
      {schedule.nextAt != null ? (
        <p className="text-sm">Next backup: {new Date(schedule.nextAt).toLocaleString()}</p>
      ) : null}
      {schedule.lastCompletedAt != null ? (
        <p className="text-sm">
          Last scheduled backup: {new Date(schedule.lastCompletedAt).toLocaleString()}
        </p>
      ) : null}
      {schedule.lastError ? <Alert>{schedule.lastError}</Alert> : null}
      {result.kind === "error" ? (
        <Alert>{result.message}</Alert>
      ) : result.kind === "saved" ? (
        <p role="status">{result.message}</p>
      ) : null}
      <Button type="submit" disabled={pending}>
        {pending ? "Saving…" : "Save backup schedule"}
      </Button>
    </form>
  );
}
