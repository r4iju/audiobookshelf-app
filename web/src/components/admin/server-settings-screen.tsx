"use client";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import { useActionState } from "react";
import { z } from "zod";
import { Button } from "@/components/ui/button";
import { TextField } from "@/components/ui/field";
import { Alert, Spinner } from "@/components/ui/status";
import { useAbs } from "@/lib/session/store";

const schema = z.object({
  serverName: z.string(),
  language: z.string(),
  loginMessage: z.string(),
  allowedOrigins: z.array(z.string()),
  rateLimitLoginRequests: z.number(),
  rateLimitLoginWindow: z.number(),
  maxScanEntries: z.number(),
  maxScanDepth: z.number(),
  maxMediaProbes: z.number(),
});
type Result = { kind: "idle" } | { kind: "saved" } | { kind: "error"; message: string };
export function ServerSettingsScreen() {
  const { client, connection } = useAbs();
  const queries = useQueryClient();
  const settings = useQuery({
    queryKey: [connection.id, "server-settings"],
    queryFn: ({ signal }) => client.get("/api/settings", schema, signal),
  });
  if (settings.isPending) return <Spinner label="Loading server settings" />;
  if (settings.isError) return <Alert>{settings.error.message}</Alert>;
  return (
    <div className="mx-auto flex max-w-3xl flex-col gap-6">
      <h1 className="text-2xl font-bold">Server settings</h1>
      <p>
        Configure server identity, sign-in policy and scan limits. Only exact browser origins are accepted;
        native clients continue to use their authenticated connections.
      </p>
      <SettingsForm
        key={connection.id}
        initial={settings.data}
        save={async (value) => {
          await client.send("PATCH", "/api/settings", value, schema);
          await queries.invalidateQueries({ queryKey: [connection.id, "server-settings"] });
        }}
      />
    </div>
  );
}
function SettingsForm({
  initial,
  save,
}: {
  initial: z.infer<typeof schema>;
  save: (value: z.infer<typeof schema>) => Promise<void>;
}) {
  const [result, action, pending] = useActionState<Result, FormData>(
    async (_old, form) => {
      const parsed = schema.safeParse({
        ...Object.fromEntries(form),
        allowedOrigins: String(form.get("allowedOrigins") ?? "")
          .split(/\r?\n/)
          .map((s) => s.trim())
          .filter(Boolean),
        ...Object.fromEntries(
          [
            "rateLimitLoginRequests",
            "rateLimitLoginWindow",
            "maxScanEntries",
            "maxScanDepth",
            "maxMediaProbes",
          ].map((key) => [key, Number(form.get(key))]),
        ),
      });
      if (!parsed.success) return { kind: "error", message: "Complete every setting with a valid value" };
      try {
        await save(parsed.data);
        return { kind: "saved" };
      } catch (error) {
        return {
          kind: "error",
          message: error instanceof Error ? error.message : "Settings could not be saved",
        };
      }
    },
    { kind: "idle" },
  );
  return (
    <form action={action} className="flex flex-col gap-4 rounded-xl bg-surface p-5">
      <TextField
        name="serverName"
        label="Server name"
        defaultValue={initial.serverName}
        required
        maxLength={256}
      />
      <TextField
        name="language"
        label="Server language"
        defaultValue={initial.language}
        required
        maxLength={5}
        help="Language code, for example en or de"
      />
      <TextField
        name="loginMessage"
        label="Sign-in message"
        defaultValue={initial.loginMessage}
        maxLength={4096}
      />
      <label className="flex flex-col gap-2 text-sm font-medium">
        Allowed browser origins (one per line)
        <textarea
          name="allowedOrigins"
          className="min-h-28 rounded-xl border border-line bg-surface p-3 font-normal"
          defaultValue={initial.allowedOrigins.join("\n")}
          placeholder="https://reader.example.com"
        />
        <span className="text-muted font-normal">
          Leave empty for the server's own origin only. Wildcards are not accepted.
        </span>
      </label>
      {[
        { name: "rateLimitLoginRequests", label: "Sign-in attempts per window", min: 1, max: 50 },
        { name: "rateLimitLoginWindow", label: "Sign-in window (milliseconds)", min: 60000, max: 3600000 },
        { name: "maxScanEntries", label: "Maximum entries per scanned folder", min: 100, max: 20000 },
        { name: "maxScanDepth", label: "Maximum folder depth", min: 1, max: 32 },
        { name: "maxMediaProbes", label: "Concurrent media probes", min: 1, max: 4 },
      ].map((field) => (
        <TextField
          key={field.name}
          name={field.name}
          label={field.label}
          type="number"
          min={field.min}
          max={field.max}
          defaultValue={String(Object.entries(initial).find(([key]) => key === field.name)?.[1] ?? "")}
          required
        />
      ))}
      {result.kind === "error" ? (
        <Alert>{result.message}</Alert>
      ) : result.kind === "saved" ? (
        <p role="status">Settings saved.</p>
      ) : null}
      <Button type="submit" variant="primary" disabled={pending}>
        {pending ? "Saving…" : "Save server settings"}
      </Button>
    </form>
  );
}
