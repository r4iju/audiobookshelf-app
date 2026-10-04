import { z } from "zod";
export const completeImportInput = z
  .object({
    digest: z.string().regex(/^[a-f0-9]{64}$/),
    sourcePath: z.string().min(1).max(4096),
    publicUrl: z.string().max(2048),
    coverMappings: z
      .array(z.object({ from: z.string().min(1).max(4096), to: z.string().min(1).max(4096) }).strict())
      .max(32),
    redirectUris: z.array(z.string().max(2048)).max(32),
  })
  .strict();
export const completeImportReport = z.object({
  digest: z.string(),
  scope: z.literal("complete"),
  canImport: z.boolean(),
  canCutover: z.boolean(),
  counts: z.object({
    openIdIdentities: z.number(),
    covers: z.number(),
    configuration: z.number(),
    sourceRows: z.number(),
  }),
  inventory: z.array(
    z.object({
      table: z.string(),
      rows: z.number(),
      disposition: z.enum(["mapped", "archived", "unsupported"]),
      fields: z.array(
        z.object({ name: z.string(), disposition: z.enum(["mapped", "archived", "unsupported"]) }),
      ),
    }),
  ),
  errors: z.array(z.object({ table: z.string(), id: z.string().optional(), message: z.string() })),
  unsupported: z.array(
    z.object({
      table: z.string(),
      id: z.string().optional(),
      fields: z.array(z.string()),
      reason: z.string(),
    }),
  ),
  notices: z.array(z.string()),
});
export type CompleteImportInput = z.infer<typeof completeImportInput>;
export type CompleteImportReport = z.infer<typeof completeImportReport>;
