"use client";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import { useActionState } from "react";
import { z } from "zod";
import { Button } from "@/components/ui/button";
import { TextField } from "@/components/ui/field";
import { Alert, Spinner } from "@/components/ui/status";
import { useAbs } from "@/lib/session/store";

const settingsSchema = z.object({
  enabled: z.boolean(),
  issuer: z.string(),
  publicUrl: z.string(),
  clientId: z.string(),
  redirectUris: z.array(z.string()),
  allowRegistration: z.boolean(),
  buttonText: z.string(),
  autoLaunch: z.boolean(),
  hasClientSecret: z.boolean(),
});
type Result = { kind: "idle" } | { kind: "saved" } | { kind: "error"; message: string };
export function OpenIdSettingsScreen() {
  const { client, connection } = useAbs(),
    queries = useQueryClient();
  const settings = useQuery({
    queryKey: [connection.id, "openid-settings"],
    queryFn: ({ signal }) => client.get("/api/admin/openid/settings", settingsSchema, signal),
  });
  if (settings.isPending) return <Spinner label="Loading OpenID settings" />;
  if (settings.isError) return <Alert>{settings.error.message}</Alert>;
  return (
    <div className="mx-auto flex max-w-3xl flex-col gap-6">
      <h1 className="text-2xl font-bold">OpenID sign-in</h1>
      <p>
        Configure your identity provider and exact client callbacks. Sign-in uses PKCE. Existing usernames are
        never automatically linked to provider accounts.
      </p>
      <OpenIdForm
        key={connection.id}
        initial={settings.data}
        save={async (value) => {
          await client.send("PATCH", "/api/admin/openid/settings", value, settingsSchema);
          await queries.invalidateQueries({ queryKey: [connection.id, "openid-settings"] });
        }}
      />
    </div>
  );
}
function OpenIdForm({
  initial,
  save,
}: {
  initial: z.infer<typeof settingsSchema>;
  save: (value: unknown) => Promise<void>;
}) {
  const [result, action, pending] = useActionState<Result, FormData>(
    async (_old, form) => {
      const value = settingsSchema.omit({ hasClientSecret: true }).safeParse({
        ...Object.fromEntries(form),
        enabled: form.has("enabled"),
        allowRegistration: form.has("allowRegistration"),
        autoLaunch: form.has("autoLaunch"),
        redirectUris: String(form.get("redirectUris") ?? "")
          .split(/\r?\n/)
          .map((s) => s.trim())
          .filter(Boolean),
      });
      if (!value.success) return { kind: "error", message: "Complete the provider settings" };
      try {
        const secret = String(form.get("clientSecret") ?? "");
        await save({
          ...value.data,
          ...(form.has("clearSecret") ? { clientSecret: null } : secret ? { clientSecret: secret } : {}),
        });
        return { kind: "saved" };
      } catch (error) {
        return {
          kind: "error",
          message: error instanceof Error ? error.message : "OpenID settings could not be saved",
        };
      }
    },
    { kind: "idle" },
  );
  return (
    <form action={action} className="flex flex-col gap-4 rounded-xl bg-surface p-5">
      <label>
        <input type="checkbox" name="enabled" defaultChecked={initial.enabled} /> Enable OpenID
      </label>
      <TextField name="issuer" label="Provider issuer URL" defaultValue={initial.issuer} maxLength={4096} />
      <TextField
        name="publicUrl"
        label="Public server URL"
        defaultValue={initial.publicUrl}
        help="Exact HTTPS address including the configured subpath, without a trailing slash. Forwarded headers cannot change this address."
        maxLength={2048}
      />
      <TextField
        name="clientId"
        label="Provider client ID"
        defaultValue={initial.clientId}
        required
        maxLength={256}
      />
      <TextField
        name="clientSecret"
        label="Replace client secret"
        type="password"
        autoComplete="new-password"
        maxLength={4096}
        help={
          initial.hasClientSecret
            ? "A secret is stored. Leave blank to retain it."
            : "No client secret is stored."
        }
      />
      <label>
        <input type="checkbox" name="clearSecret" /> Remove stored secret (public provider client)
      </label>
      <label className="flex flex-col gap-2 text-sm font-medium">
        Allowed client callbacks (one exact URI per line)
        <textarea
          name="redirectUris"
          className="min-h-28 rounded-xl border border-line bg-surface p-3 font-normal"
          defaultValue={initial.redirectUris.join("\n")}
        />
        <span className="text-muted font-normal">
          Include your browser URL ending in /oauth and the exact callback configured in each native app.
          Wildcards are not accepted.
        </span>
      </label>
      <label>
        <input type="checkbox" name="allowRegistration" defaultChecked={initial.allowRegistration} /> Allow
        new provider accounts to register as ordinary users
      </label>
      <TextField
        name="buttonText"
        label="Sign-in button text"
        defaultValue={initial.buttonText}
        maxLength={256}
      />
      <label>
        <input type="checkbox" name="autoLaunch" defaultChecked={initial.autoLaunch} /> Automatically open
        provider sign-in
      </label>
      {result.kind === "error" ? (
        <Alert>{result.message}</Alert>
      ) : result.kind === "saved" ? (
        <Alert tone="info">OpenID settings saved. Pending sign-ins were reset.</Alert>
      ) : null}
      <Button type="submit" disabled={pending}>
        {pending ? "Validating provider…" : "Save OpenID settings"}
      </Button>
    </form>
  );
}
