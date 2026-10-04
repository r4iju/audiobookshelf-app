import { z } from "zod";
export const mediaInspectSchema = z
  .object({
    sourcePath: z.string().min(1).max(4096),
    mappings: z
      .array(z.object({ from: z.string().min(1).max(4096), to: z.string().min(1).max(4096) }).strict())
      .max(32),
  })
  .strict();
export const mediaCommitSchema = mediaInspectSchema.extend({
  expectedDigest: z.string().regex(/^[a-f0-9]{64}$/),
});
export const mediaImportReportSchema = z.object({
  digest: z.string(),
  scope: z.literal("media"),
  canImport: z.boolean(),
  canCutover: z.literal(false),
  counts: z.object({
    libraries: z.number(),
    items: z.number(),
    files: z.number(),
    progress: z.number(),
    sessions: z.number(),
    bookmarks: z.number(),
    listeningSeconds: z.number(),
  }),
  errors: z.array(z.object({ table: z.string(), id: z.string().optional(), message: z.string() })),
  remainingData: z.array(
    z.object({ table: z.string(), rows: z.number(), recordIds: z.array(z.string()).optional() }),
  ),
  archivedFields: z.array(z.object({ table: z.string(), fields: z.array(z.string()) })),
  notices: z.array(z.string()),
});
export type MediaImportReport = z.infer<typeof mediaImportReportSchema>;

export const listImportSchema = z.object({ digest: z.string().regex(/^[a-f0-9]{64}$/) });
export const listImportReportSchema = z.object({
  digest: z.string(),
  scope: z.literal("lists"),
  canImport: z.boolean(),
  canCutover: z.literal(false),
  counts: z.object({ collections: z.number(), playlists: z.number(), members: z.number() }),
  errors: z.array(z.object({ table: z.string(), id: z.string(), message: z.string() })),
  unsupported: z.array(z.object({ table: z.string(), id: z.string(), fields: z.array(z.string()) })),
  notices: z.array(z.string()),
});
export type ListImportReport = z.infer<typeof listImportReportSchema>;
