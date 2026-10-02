import { expect, it } from "vitest";
import { z } from "zod";
import { translate } from "@/i18n/i18n";
import { loaders } from "@/i18n/loaders";
import { AbsError, createAbsClient } from "@/lib/abs/client";
import { errorMessage } from "./errors";

it("presents malformed server replies in the selected language without exposing schema internals", async () => {
  const client = createAbsClient({
    connection: {
      id: "synthetic",
      serverUrl: "https://example.invalid",
      username: "qa",
      userId: "qa",
      auth: { kind: "legacy", token: "synthetic" },
    },
    fetcher: async () => new Response('{"privateField":"unexpected"}', { status: 200 }),
    saveAuth: () => {},
  });
  const error = await client.get("/api/me", z.object({ id: z.string() })).catch((caught: unknown) => caught);
  expect(error).toBeInstanceOf(AbsError);
  const { default: strings } = await loaders.de();
  expect(errorMessage(translate(strings, "de"), error)).toBe(strings.WebErrorGeneric);
});
