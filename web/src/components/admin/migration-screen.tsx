"use client";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import { useActionState } from "react";
import { z } from "zod";
import { Button, ButtonLink } from "@/components/ui/button";
import { TextField } from "@/components/ui/field";
import { Section } from "@/components/ui/section";
import { Alert, EmptyState, Spinner } from "@/components/ui/status";
import { useAbs } from "@/lib/session/store";

const backupSchema = z.object({
  id: z.string().uuid(),
  createdAt: z.number(),
  bytes: z.number(),
  sha256: z.string(),
  schema: z.string(),
});
const backupsSchema = z.object({ backups: z.array(backupSchema) });
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
      <Section title="Product backups">
        <p className="text-sm text-muted">
          Backups preserve this installation’s SQLite data. Keep your original media mounts and data folder
          separately. Only the owner can create or restore backups.
        </p>
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
                <BackupAction backupId={backup.id} />
              </li>
            ))}
          </ul>
        ) : (
          <EmptyState title="No backups yet" />
        )}
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
            Restoring replaces the current database. Create a current backup first, then enter RESTORE to
            confirm.
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
