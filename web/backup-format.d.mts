import type { DatabaseSync } from "node:sqlite";
import type { z } from "zod";
export type BackupManifest = {
  id: string;
  sha256: string;
  createdAt: number;
  schema: string;
  bytes: number;
  scheduled?: boolean;
  formatVersion: 2;
  schemaVersion: number;
  keyIncluded: true;
  keySha256: string;
  media: { included: false; requiredMounts: string[]; managedDirectory: string };
};
export const maximumSchemaVersion: number;
export const backupManifestSchema: z.ZodType<BackupManifest>;
export function databaseSchema(db: DatabaseSync): { tables: Record<string, unknown>[]; digest: string };
export function pinnedDatabase(filename: string): {
  db: DatabaseSync;
  digest: string;
  bytes: number;
  close(): void;
};
export function validateDatabase(db: DatabaseSync): void;
export function readBackup(
  folder: string,
  id: string,
): ReturnType<typeof pinnedDatabase> & { manifest: BackupManifest; key: string };
export function createSnapshot(
  db: DatabaseSync,
  directory: string,
  authorize?: () => void,
  scheduledId?: string,
): Promise<BackupManifest>;
