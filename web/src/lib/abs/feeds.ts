import { z } from "zod";

export const feedSchema = z.looseObject({
  id: z.string(),
  entityId: z.string().nullish(),
  feedUrl: z.string(),
  meta: z
    .looseObject({
      title: z.string().nullish(),
      preventIndexing: z.boolean().nullish(),
      ownerName: z.string().nullish(),
      ownerEmail: z.string().nullish(),
    })
    .nullish(),
});
export type Feed = z.infer<typeof feedSchema>;

/** The legacy client's slug cleaning: the server takes the slug as given and serves the feed at /feed/<slug>. */
export function feedSlug(input: string) {
  return input
    .normalize("NFD")
    .replace(/[̀-ͯ]/g, "")
    .toLowerCase()
    .replace(/[·/,:;.\s]+/g, "-")
    .replace(/[^a-z0-9_-]/g, "")
    .replace(/-+/g, "-")
    .replace(/^-|-$/g, "");
}
