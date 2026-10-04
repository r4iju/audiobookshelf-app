import { z } from "zod";

const name = z.string().trim().min(1).max(256);
export const metadataEditInput = z
  .object({
    metadata: z
      .object({
        title: name.optional(),
        subtitle: z.string().max(1024).nullable().optional(),
        description: z.string().max(16384).nullable().optional(),
        authors: z
          .array(z.object({ id: z.string().max(256).optional(), name }))
          .max(100)
          .optional(),
        series: z
          .array(
            z.object({
              id: z.string().max(256).optional(),
              name,
              sequence: z.string().max(64).nullable().optional(),
            }),
          )
          .max(100)
          .optional(),
        narrators: z.array(name).max(100).optional(),
        genres: z.array(name).max(100).optional(),
        publisher: z.string().max(256).nullable().optional(),
        publishedYear: z.string().max(32).nullable().optional(),
        language: z.string().max(64).nullable().optional(),
        explicit: z.boolean().optional(),
      })
      .strict()
      .optional(),
    tags: z.array(name).max(100).optional(),
  })
  .strict();
export const providerSettingsInput = z
  .object({ enabled: z.boolean(), searchUrl: z.url().max(2048) })
  .strict();
export const metadataMatchesSchema = z.object({
  results: z
    .array(
      z.object({
        key: z.string(),
        title: z.string(),
        authors: z.array(z.string()),
        publishedYear: z.string().nullable(),
      }),
    )
    .max(20),
});
