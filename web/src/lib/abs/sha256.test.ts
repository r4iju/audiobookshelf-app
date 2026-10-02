import { createHash } from "node:crypto";
import { describe, expect, it } from "vitest";
import { sha256 } from "./sha256";

const reference = (text: string) => new Uint8Array(createHash("sha256").update(text).digest());

describe("sha256", () => {
  it("matches the standard digest for empty, one-block, multi-block and non-ASCII input", () => {
    for (const text of [
      "",
      "abc",
      "abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq",
      "x".repeat(55),
      "x".repeat(56),
      "x".repeat(64),
      "x".repeat(1000),
      "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk",
      "Bücher und Hörbücher",
    ])
      expect(sha256(new TextEncoder().encode(text))).toEqual(reference(text));
  });
});
