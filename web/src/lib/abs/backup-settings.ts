import { z } from "zod";
export const backupConfigurationSchema = z
  .object({
    enabled: z.boolean(),
    intervalMinutes: z.number().int().min(60).max(43200),
    keepLast: z.number().int().min(1).max(50),
  })
  .strict();
export const backupScheduleSchema = z.object({
  nextAt: z.number().nullable(),
  lastCompletedAt: z.number().nullable(),
  lastError: z.string().nullable(),
});
export const backupSettingsSchema = z.object({
  configuration: backupConfigurationSchema,
  schedule: backupScheduleSchema,
});
