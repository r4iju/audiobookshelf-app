import { describe, expect, it } from "vitest";
import { completeOpenId } from "./auth";

const pending = {
  serverUrl: "https://abs.example",
  state: "state-1",
  verifier: "verifier-1",
  redirectUri: "https://abs.example/web/oauth",
  returnTo: "/",
};

/** A response as fetch reports it after following the server's redirects. */
function followed(url: string, body: string, init: ResponseInit = { status: 200 }) {
  const response = new Response(body, init);
  Object.defineProperties(response, { url: { value: url }, redirected: { value: true } });
  return response;
}

describe("completeOpenId", () => {
  it("reports the server's refusal, which 2.30.0 sends as a redirect to its own login page", async () => {
    const result = await completeOpenId(
      pending,
      new URLSearchParams({ code: "undefined", state: "state-1" }),
      async () => followed("https://abs.example/login?error=Unauthorized&autoLaunch=0", "<!doctype html>"),
    );
    expect(result).toEqual({ ok: false, reason: "rejected", detail: "Unauthorized" });
  });

  it("ignores a provider error that does not carry this sign-in's state", async () => {
    const forged = await completeOpenId(
      pending,
      new URLSearchParams({ error: "Your account is locked, call +1 555 0100" }),
      async () => new Response(null, { status: 500 }),
    );
    expect(forged).toEqual({ ok: false, reason: "state-mismatch" });
    const genuine = await completeOpenId(
      pending,
      new URLSearchParams({ error: "access_denied", state: "state-1" }),
      async () => new Response(null, { status: 500 }),
    );
    expect(genuine).toEqual({ ok: false, reason: "provider-error", detail: "access_denied" });
  });
});
