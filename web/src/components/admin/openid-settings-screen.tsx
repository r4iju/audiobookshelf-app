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
  const { t } = useI18n();
  const { client, connection } = useAbs(),
    queries = useQueryClient();
  const settings = useQuery({
    queryKey: [connection.id, "openid-settings"],
    queryFn: ({ signal }) => client.get("/api/admin/openid/settings", settingsSchema, signal),
  });
  if (settings.isPending) return <Spinner label={t("WebAdminLoadingOpenIDSettings")} />;
  if (settings.isError) return <Alert>{adminMessage(settings.error.message, t)}</Alert>;
  return (
    <div className="mx-auto flex max-w-3xl flex-col gap-6">
      <h1 className="text-2xl font-bold">{t("WebAdminOpenIDSignIn")}</h1>
      <p>{t("WebAdminConfigureYourIdentityProviderAndExactClient")}</p>
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
  const feedbackId = useId();
  const { t } = useI18n();
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
    <form
      aria-describedby={result.kind === "error" ? feedbackId : undefined}
      action={action}
      className="flex flex-col gap-4 rounded-xl bg-surface p-5"
    >
      <label>
        <input type="checkbox" name="enabled" defaultChecked={initial.enabled} />
        {t("WebAdminEnableOpenID")}
      </label>
      <TextField
        name="issuer"
        label={t("WebAdminProviderIssuerURL")}
        defaultValue={initial.issuer}
        maxLength={4096}
      />
      <TextField
        name="publicUrl"
        label={t("WebAdminPublicServerURL")}
        defaultValue={initial.publicUrl}
        help={t("WebAdminExactHTTPSAddressIncludingTheConfiguredSubpath")}
        maxLength={2048}
      />
      <TextField
        name="clientId"
        label={t("WebAdminProviderClientID")}
        defaultValue={initial.clientId}
        required
        maxLength={256}
      />
      <TextField
        name="clientSecret"
        label={t("WebAdminReplaceClientSecret")}
        type="password"
        autoComplete="new-password"
        maxLength={4096}
        help={
          initial.hasClientSecret
            ? t("WebAdminASecretIsStoredLeaveBlankTo")
            : t("WebAdminNoClientSecretIsStored")
        }
      />
      <label>
        <input type="checkbox" name="clearSecret" />
        {t("WebAdminRemoveStoredSecretPublicProviderClient")}
      </label>
      <label className="flex flex-col gap-2 text-sm font-medium">
        {t("WebAdminAllowedClientCallbacksOneExactURIPer")}
        <textarea
          name="redirectUris"
          className="min-h-28 rounded-xl border border-line bg-surface p-3 font-normal"
          defaultValue={initial.redirectUris.join("\n")}
        />
        <span className="text-muted font-normal">{t("WebAdminIncludeYourBrowserURLEndingInOauth")}</span>
      </label>
      <label>
        <input type="checkbox" name="allowRegistration" defaultChecked={initial.allowRegistration} />
        {t("WebAdminAllowNewProviderAccountsToRegisterAs")}
      </label>
      <TextField
        name="buttonText"
        label={t("WebAdminSignInButtonText")}
        defaultValue={initial.buttonText}
        maxLength={256}
      />
      <label>
        <input type="checkbox" name="autoLaunch" defaultChecked={initial.autoLaunch} />
        {t("WebAdminAutomaticallyOpenProviderSignIn")}
      </label>
      {result.kind === "error" ? (
        <FormFeedback submission={result} id={feedbackId}>
          {adminMessage(result.message, t)}
        </FormFeedback>
      ) : result.kind === "saved" ? (
        <Alert tone="info">{t("WebAdminOpenIDSettingsSavedPendingSignInsWere")}</Alert>
      ) : null}
      <Button type="submit" disabled={pending}>
        {pending ? t("WebAdminValidatingProvider") : t("WebAdminSaveOpenIDSettings")}
      </Button>
    </form>
  );
}
