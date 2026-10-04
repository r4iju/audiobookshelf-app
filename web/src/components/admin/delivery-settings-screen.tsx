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

const smtpSchema = z.object({
  host: z.string(),
  port: z.number(),
  secure: z.boolean(),
  fromAddress: z.string(),
  username: z.string(),
  hasPassword: z.boolean(),
});
const deviceSchema = z.object({
  name: z.string().min(1),
  email: z.email(),
  availabilityOption: z.enum(["adminOrUp", "userOrUp", "guestOrUp", "specificUsers"]),
  users: z.array(z.string()),
});
const devicesSchema = z.object({ ereaderDevices: z.array(deviceSchema) });
const accountsSchema = z.object({ users: z.array(z.object({ id: z.string(), username: z.string() })) });
type Result = { kind: "idle" } | { kind: "saved" } | { kind: "error"; message: string };
function message(error: unknown): Result {
  return { kind: "error", message: error instanceof Error ? error.message : "Settings could not be saved" };
}
function ResultMessage({ value, id }: { value: Result; id?: string }) {
  const { t } = useI18n();
  return value.kind === "error" ? (
    <FormFeedback submission={value} id={id}>
      {adminMessage(value.message, t)}
    </FormFeedback>
  ) : value.kind === "saved" ? (
    <Alert tone="info">{t("WebAdminSettingsSaved")}</Alert>
  ) : null;
}
export function DeliverySettingsScreen() {
  const { t } = useI18n();
  const { client, connection } = useAbs(),
    queries = useQueryClient();
  const smtp = useQuery({
    queryKey: [connection.id, "smtp-settings"],
    queryFn: ({ signal }) => client.get("/api/emails/settings", smtpSchema, signal),
  });
  const devices = useQuery({
    queryKey: [connection.id, "delivery-devices"],
    queryFn: ({ signal }) => client.get("/api/emails/ereader-devices", devicesSchema, signal),
  });
  const accounts = useQuery({
    queryKey: [connection.id, "delivery-accounts"],
    queryFn: ({ signal }) => client.get("/api/users", accountsSchema, signal),
  });
  if (accounts.isPending) return <Spinner label={t("WebAdminLoadingDeliveryAccounts")} />;
  if (accounts.isError) return <Alert>{adminMessage(accounts.error.message, t)}</Alert>;
  if (smtp.isPending || devices.isPending) return <Spinner label={t("WebAdminLoadingDeliverySettings")} />;
  if (smtp.isError) return <Alert>{adminMessage(smtp.error.message, t)}</Alert>;
  if (devices.isError) return <Alert>{adminMessage(devices.error.message, t)}</Alert>;
  async function saveDevices(value: z.infer<typeof devicesSchema>) {
    await client.send("POST", "/api/emails/ereader-devices", value, devicesSchema);
    await queries.invalidateQueries({ queryKey: [connection.id, "delivery-devices"] });
    await queries.invalidateQueries({ queryKey: [connection.id, "ereader-devices"] });
  }
  return (
    <div className="mx-auto flex max-w-3xl flex-col gap-6">
      <h1 className="text-2xl font-bold">{t("WebAdminEReaderDelivery")}</h1>
      <p>{t("WebAdminConfigureSMTPAndTrustedDestinationAddressesReaders")}</p>
      <SmtpForm
        key={connection.id}
        initial={smtp.data}
        save={async (value) => {
          await client.send("PATCH", "/api/emails/settings", value, smtpSchema);
          await queries.invalidateQueries({ queryKey: [connection.id, "smtp-settings"] });
        }}
      />
      <h2 className="text-xl font-semibold">{t("WebAdminDevices")}</h2>
      {devices.data.ereaderDevices.length ? (
        devices.data.ereaderDevices.map((device) => (
          <DeviceForm
            key={device.name}
            accounts={accounts.data.users}
            initial={device}
            save={async (value) =>
              saveDevices({
                ereaderDevices: devices.data.ereaderDevices.map((old) =>
                  old.name === device.name ? value : old,
                ),
              })
            }
            remove={async () =>
              saveDevices({
                ereaderDevices: devices.data.ereaderDevices.filter((old) => old.name !== device.name),
              })
            }
          />
        ))
      ) : (
        <p>{t("WebAdminNoDeliveryDevicesConfigured")}</p>
      )}
      <h2 className="text-xl font-semibold">{t("WebAdminAddDevice")}</h2>
      <DeviceForm
        key={connection.id + "new"}
        accounts={accounts.data.users}
        initial={{ name: "", email: "", availabilityOption: "userOrUp", users: [] }}
        save={async (value) => saveDevices({ ereaderDevices: [...devices.data.ereaderDevices, value] })}
      />
    </div>
  );
}
function SmtpForm({
  initial,
  save,
}: {
  initial: z.infer<typeof smtpSchema>;
  save: (value: unknown) => Promise<void>;
}) {
  const feedbackId = useId();
  const { t } = useI18n();
  const [result, action, pending] = useActionState<Result, FormData>(
    async (_old, form) => {
      try {
        const value = smtpSchema
          .omit({ hasPassword: true })
          .parse({ ...Object.fromEntries(form), port: Number(form.get("port")), secure: form.has("secure") });
        const password = String(form.get("password") ?? "");
        await save({
          ...value,
          ...(form.has("clearPassword") ? { password: null } : password ? { password } : {}),
        });
        return { kind: "saved" };
      } catch (error) {
        return message(error);
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
      <h2 className="text-xl font-semibold">SMTP</h2>
      <TextField name="host" label={t("WebAdminSMTPHost")} defaultValue={initial.host} maxLength={253} />
      <TextField
        name="port"
        label={t("WebAdminSMTPPort")}
        type="number"
        min={1}
        max={65535}
        defaultValue={String(initial.port)}
        required
      />
      <label>
        <input name="secure" type="checkbox" defaultChecked={initial.secure} />
        {t("WebAdminUseImplicitTLSUsuallyPort465")}
      </label>
      <p className="text-sm text-muted">{t("WebAdminOtherProductionConnectionsRequireSTARTTLSAndValid")}</p>
      <TextField
        name="fromAddress"
        label={t("WebAdminSenderEmail")}
        type="email"
        defaultValue={initial.fromAddress}
        required
      />
      <TextField
        name="username"
        label={t("WebAdminSMTPUsername")}
        defaultValue={initial.username}
        maxLength={256}
      />
      <TextField
        name="password"
        label={t("WebAdminReplaceSMTPPassword")}
        type="password"
        autoComplete="new-password"
        maxLength={4096}
        help={
          initial.hasPassword ? t("WebAdminAPasswordIsStoredLeaveBlankTo") : t("WebAdminNoPasswordIsStored")
        }
      />
      <label>
        <input name="clearPassword" type="checkbox" />
        {t("WebAdminRemoveStoredPassword")}
      </label>
      <ResultMessage id={feedbackId} value={result} />
      <Button type="submit" disabled={pending}>
        {t("WebAdminSaveSMTPSettings")}
      </Button>
    </form>
  );
}
function DeviceForm({
  initial,
  save,
  remove,
  accounts,
}: {
  accounts: z.infer<typeof accountsSchema>["users"];
  initial: z.infer<typeof deviceSchema>;
  save: (value: z.infer<typeof deviceSchema>) => Promise<void>;
  remove?: () => Promise<void>;
}) {
  const feedbackId = useId();
  const { t } = useI18n();
  const [result, action, pending] = useActionState<Result, FormData>(
    async (_old, form) => {
      try {
        if (form.get("intent") === "remove") {
          if (remove) await remove();
          return { kind: "saved" };
        }
        const value = deviceSchema.parse({ ...Object.fromEntries(form), users: form.getAll("users") });
        await save(value);
        return { kind: "saved" };
      } catch (error) {
        return message(error);
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
        name="name"
        label={t("WebAdminDeviceName")}
        defaultValue={initial.name}
        required
        maxLength={256}
      />
      <TextField
        name="email"
        label={t("WebAdminDeviceEmail")}
        type="email"
        defaultValue={initial.email}
        required
      />
      <label className="flex flex-col gap-2">
        {t("WebAdminAvailableTo")}
        <select
          name="availabilityOption"
          defaultValue={initial.availabilityOption}
          className="rounded-xl border border-line bg-surface p-3"
        >
          <option value="adminOrUp">{t("WebAdminAdministrators")}</option>
          <option value="userOrUp">{t("WebAdminUsersAndAdministrators")}</option>
          <option value="guestOrUp">{t("WebAdminAllSignedInAccounts")}</option>
          <option value="specificUsers">{t("WebAdminSelectedAccounts")}</option>
        </select>
      </label>
      <label className="flex flex-col gap-2">
        {t("WebAdminSelectedAccountsWhenUsingSelectedAvailability")}
        <select
          multiple
          name="users"
          defaultValue={initial.users}
          className="min-h-28 rounded-xl border border-line bg-surface p-3"
        >
          {accounts.map((account) => (
            <option key={account.id} value={account.id}>
              {account.username}
            </option>
          ))}
        </select>
      </label>
      <ResultMessage id={feedbackId} value={result} />
      <div className="flex flex-wrap gap-3">
        <Button type="submit" disabled={pending}>
          {t("WebAdminSaveDevice")}
        </Button>
        {remove ? (
          <Button type="submit" name="intent" value="remove" variant="ghost" disabled={pending}>
            {t("WebAdminRemoveDevice")}
          </Button>
        ) : null}
      </div>
    </form>
  );
}
