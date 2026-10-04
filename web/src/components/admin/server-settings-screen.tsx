"use client";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import { useActionState, useId } from "react";
import { z } from "zod";
import { Button } from "@/components/ui/button";
import { TextField } from "@/components/ui/field";
import { FormFeedback } from "@/components/ui/form-feedback";
import { Alert, Spinner } from "@/components/ui/status";
import { useI18n } from "@/i18n/i18n";
import { adminMessage } from "@/lib/abs/administration-messages";
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
  const { t } = useI18n();
  const { client, connection } = useAbs();
  const queries = useQueryClient();
  const settings = useQuery({
    queryKey: [connection.id, "server-settings"],
    queryFn: ({ signal }) => client.get("/api/settings", schema, signal),
  });
  if (settings.isPending) return <Spinner label={t("WebAdminLoadingServerSettings")} />;
  if (settings.isError) return <Alert>{adminMessage(settings.error.message, t)}</Alert>;
  return (
    <div className="mx-auto flex max-w-3xl flex-col gap-6">
      <h1 className="text-2xl font-bold">{t("WebAdminServerSettings")}</h1>
      <p>{t("WebAdminConfigureServerIdentitySignInPolicyAnd")}</p>
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
  const feedbackId = useId();
  const { t } = useI18n();
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
    <form
      aria-describedby={result.kind === "error" ? feedbackId : undefined}
      action={action}
      className="flex flex-col gap-4 rounded-xl bg-surface p-5"
    >
      <TextField
        name="serverName"
        label={t("WebAdminServerName")}
        defaultValue={initial.serverName}
        required
        maxLength={256}
      />
      <TextField
        name="language"
        label={t("WebAdminServerLanguage")}
        defaultValue={initial.language}
        required
        maxLength={5}
        help={t("WebAdminLanguageCodeForExampleEnOrDe")}
      />
      <TextField
        name="loginMessage"
        label={t("WebAdminSignInMessage")}
        defaultValue={initial.loginMessage}
        maxLength={4096}
      />
      <label className="flex flex-col gap-2 text-sm font-medium">
        {t("WebAdminAllowedBrowserOriginsOnePerLine")}
        <textarea
          name="allowedOrigins"
          className="min-h-28 rounded-xl border border-line bg-surface p-3 font-normal"
          defaultValue={initial.allowedOrigins.join("\n")}
          placeholder="https://reader.example.com"
        />
        <span className="text-muted font-normal">{t("WebAdminLeaveEmptyForTheServerSOwn")}</span>
      </label>
      {[
        { name: "rateLimitLoginRequests", label: t("WebAdminSignInAttemptsPerWindow"), min: 1, max: 50 },
        {
          name: "rateLimitLoginWindow",
          label: t("WebAdminSignInWindowMilliseconds"),
          min: 60000,
          max: 3600000,
        },
        { name: "maxScanEntries", label: t("WebAdminMaximumEntriesPerScannedFolder"), min: 100, max: 20000 },
        { name: "maxScanDepth", label: t("WebAdminMaximumFolderDepth"), min: 1, max: 32 },
        { name: "maxMediaProbes", label: t("WebAdminConcurrentMediaProbes"), min: 1, max: 4 },
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
        <FormFeedback submission={result} id={feedbackId}>
          {adminMessage(result.message, t)}
        </FormFeedback>
      ) : result.kind === "saved" ? (
        <p role="status">{t("WebAdminSettingsSaved")}</p>
      ) : null}
      <Button type="submit" variant="primary" disabled={pending}>
        {pending ? t("WebAdminSaving") : t("WebAdminSaveServerSettings")}
      </Button>
    </form>
  );
}
