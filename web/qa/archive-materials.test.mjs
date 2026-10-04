import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

test("the served comic decoder excludes the old OpenSSL binary and has matching build provenance", async () => {
  const binary = await readFile(new URL("../public/libarchive/libarchive.wasm", import.meta.url));
  assert.ok(WebAssembly.validate(binary), "the served decoder is a valid WebAssembly module");
  assert.equal(
    /OpenSSL|SSLeay/i.test(binary.toString("latin1")),
    false,
    "the public decoder must exclude pre-3.0 OpenSSL",
  );
  const provenance = JSON.parse(
    await readFile(new URL("../vendor/libarchive/provenance.json", import.meta.url), "utf8"),
  );
  assert.equal(provenance.openssl, false);
  assert.ok(provenance.sourceSha && provenance.emsdkImage && provenance.inputs.length);
});
