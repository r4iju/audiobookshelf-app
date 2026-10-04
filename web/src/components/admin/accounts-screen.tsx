"use client";

import { useQuery, useQueryClient } from "@tanstack/react-query";
import { useActionState, useId } from "react";
import { z } from "zod";
import { Button } from "@/components/ui/button";
import { TextField, Toggle } from "@/components/ui/field";
import { FormFeedback } from "@/components/ui/form-feedback";
import { Section } from "@/components/ui/section";
import { SelectField } from "@/components/ui/select";
import { Alert, EmptyState, Spinner } from "@/components/ui/status";
import { useI18n } from "@/i18n/i18n";
import { adminMessage } from "@/lib/abs/administration-messages";
import { permissionsSchema, userSchema } from "@/lib/abs/schemas";
import { useAbs } from "@/lib/session/store";

const accountSchema = userSchema.extend({
  isActive: z.boolean(),
  itemTagsSelected: z.array(z.string()),
  permissions: permissionsSchema.extend({
    accessAllLibraries: z.boolean(),
    accessAllTags: z.boolean(),
    selectedTagsNotAccessible: z.boolean(),
  }),
});
type ManagedAccount = z.infer<typeof accountSchema>;
const responseSchema = z.object({ users: z.array(accountSchema) });
const formSchema = z.object({
  username: z.string().trim().min(3).max(64),
  password: z.string().max(512),
  type: z.enum(["user", "guest", "admin"]),
  libraries: z.string(),
  tags: z.string(),
});
type Result = { kind: "idle" } | { kind: "success"; message: string } | { kind: "error"; message: string };
const split = (value: string) =>
  value
    .split(",")
    .map((value) => value.trim())
    .filter(Boolean);

export function AccountsScreen() {
  const { t } = useI18n();
  const { client, connection } = useAbs();
  const accounts = useQuery({
    queryKey: [connection.id, "administration", "accounts"],
    queryFn: ({ signal }) => client.get("/api/users", responseSchema, signal),
  });
  return (
    <div className="mx-auto flex max-w-3xl flex-col gap-6">
      <h1 className="text-2xl font-bold">{t("WebAdminAccounts")}</h1>
      <p className="text-muted">{t("WebAdminAccountChangesRevokeExistingSignInsLibrary")}</p>
      {accounts.isPending ? (
        <Spinner label={t("WebAdminLoadingAccounts")} />
      ) : accounts.isError ? (
        <Alert>{adminMessage(accounts.error.message, t)}</Alert>
      ) : (
        <>
          <Section title={t("WebAdminCreateAccount")}>
            <AccountForm />
          </Section>
          {accounts.data.users.length ? (
            accounts.data.users.map((account) => (
              <Section key={account.id} title={account.username}>
                {account.type === "root" ? (
                  <p className="text-sm text-muted">{t("WebAdminOwnerAccountProtectedFromRemovalAndRole")}</p>
                ) : (
                  <AccountForm key={JSON.stringify(account)} account={account} />
                )}
              </Section>
            ))
          ) : (
            <EmptyState title={t("WebAdminNoAccounts")} />
          )}
        </>
      )}
    </div>
  );
}

function AccountForm({ account }: { account?: ManagedAccount }) {
  const feedbackId = useId();
  const { t } = useI18n();
  const choices = [
    { value: "user", label: t("LabelUser") },
    { value: "guest", label: t("WebAdminGuest") },
    { value: "admin", label: t("WebAdminAdministrator") },
  ];
  const policyFields = [
    ["download", t("WebAdminAllowDownloads")],
    ["update", t("WebAdminAllowMetadataEdits")],
    ["delete", t("WebAdminAllowMediaDeletion")],
    ["upload", t("WebAdminAllowUploads")],
    ["accessExplicitContent", t("WebAdminAllowExplicitContent")],
    ["accessAllLibraries", t("WebAdminAllowAllLibraries")],
    ["accessAllTags", t("WebAdminAllowAllTags")],
    ["selectedTagsNotAccessible", t("WebAdminExcludeSelectedTagsInsteadOfAllowingThem")],
  ] as const;
  const { client, connection } = useAbs();
  const queries = useQueryClient();
  const [result, submit, pending] = useActionState<Result, FormData>(
    async (_previous, data) => {
      try {
        const operation = data.get("operation") ?? "save";
        if (account && (operation === "remove" || operation === "revoke")) {
          await client.command(
            operation === "remove" ? "DELETE" : "POST",
            `/api/users/${account.id}${operation === "revoke" ? "/revoke" : ""}`,
            {},
          );
        } else {
          const fields = formSchema.parse(Object.fromEntries(data));
          if (!account && fields.password.length < 12)
            throw new Error("Use a password with at least 12 characters");
          const payload = {
            username: fields.username,
            ...(fields.password ? { password: fields.password } : {}),
            type: fields.type,
            isActive: data.has("isActive"),
            permissions: Object.fromEntries(policyFields.map(([key]) => [key, data.has(key)])),
            librariesAccessible: split(fields.libraries),
            itemTagsSelected: split(fields.tags),
          };
          await client.send(
            account ? "PATCH" : "POST",
            account ? `/api/users/${account.id}` : "/api/users",
            payload,
            accountSchema,
          );
        }
        await queries.invalidateQueries({ queryKey: [connection.id, "administration", "accounts"] });
        return {
          kind: "success",
          message:
            operation === "remove"
              ? "Account removed"
              : operation === "revoke"
                ? "Sign-ins revoked"
                : "Account saved",
        };
      } catch (error) {
        return {
          kind: "error",
          message:
            error instanceof z.ZodError
              ? "Check the account fields"
              : error instanceof Error
                ? error.message
                : "Could not save account",
        };
      }
    },
    { kind: "idle" },
  );
  return (
    <form
      aria-describedby={result.kind === "error" ? feedbackId : undefined}
      aria-label={account ? t("WebAccountForm", account.username) : t("WebAdminCreateAccount")}
      action={submit}
      className="flex flex-col gap-4"
    >
      <fieldset disabled={pending} className="flex flex-col gap-4">
        <div className="grid gap-4 sm:grid-cols-2">
          <TextField
            name="username"
            label={t("LabelUsername")}
            required
            minLength={3}
            maxLength={64}
            defaultValue={account?.username}
            autoComplete="off"
          />
          <TextField
            name="password"
            type="password"
            label={account ? t("WebAdminNewPassword") : t("LabelPassword")}
            required={!account}
            minLength={12}
            maxLength={512}
            autoComplete="new-password"
            help={
              account ? t("WebAdminLeaveEmptyToKeepTheExistingPassword") : t("WebAdminUseAtLeast12Characters")
            }
          />
          <SelectField
            name="type"
            label={t("WebAdminRole")}
            options={choices}
            defaultValue={account?.type ?? "user"}
          />
          <Toggle
            name="isActive"
            label={t("WebAdminAccountEnabled")}
            defaultChecked={account?.isActive ?? true}
          />
        </div>
        <div className="grid gap-x-6 sm:grid-cols-2">
          {policyFields.map(([key, label]) => (
            <Toggle
              key={key}
              name={key}
              label={label}
              defaultChecked={
                account
                  ? account.permissions[key]
                  : ["download", "accessAllLibraries", "accessAllTags"].includes(key)
              }
            />
          ))}
        </div>
        <TextField
          name="libraries"
          label={t("WebAdminAllowedLibraryIDs")}
          help={t("WebAdminSeparateIDsWithCommasUsedWhenAll")}
          defaultValue={account?.librariesAccessible.join(", ") ?? ""}
        />
        <TextField
          name="tags"
          label={t("WebAdminSelectedTags")}
          help={t("WebAdminSeparateTagsWithCommasUsedWhenAll")}
          defaultValue={account?.itemTagsSelected.join(", ") ?? ""}
        />
        <div className="flex flex-wrap gap-3">
          <Button type="submit" name="operation" value="save" variant="primary">
            {pending ? t("WebAdminSaving") : account ? t("WebAdminSaveAccount") : t("WebAdminCreateAccount")}
          </Button>
          {account ? (
            <>
              <Button type="submit" name="operation" value="revoke" formNoValidate>
                {t("WebAdminRevokeSignIns")}
              </Button>
              <Button type="submit" name="operation" value="remove" formNoValidate>
                {t("WebAdminRemoveAccount")}
              </Button>
            </>
          ) : null}
        </div>
      </fieldset>
      {result.kind !== "idle" ? (
        <FormFeedback
          submission={result}
          id={feedbackId}
          tone={result.kind === "success" ? "info" : "danger"}
        >
          {adminMessage(result.message, t)}
        </FormFeedback>
      ) : null}
    </form>
  );
}
