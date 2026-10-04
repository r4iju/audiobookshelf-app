"use client";

import { useQuery, useQueryClient } from "@tanstack/react-query";
import { useActionState } from "react";
import { z } from "zod";
import { Button } from "@/components/ui/button";
import { TextField, Toggle } from "@/components/ui/field";
import { Section } from "@/components/ui/section";
import { SelectField } from "@/components/ui/select";
import { Alert, EmptyState, Spinner } from "@/components/ui/status";
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
const choices = [
  { value: "user", label: "User" },
  { value: "guest", label: "Guest" },
  { value: "admin", label: "Administrator" },
];
const policyFields = [
  ["download", "Allow downloads"],
  ["update", "Allow metadata edits"],
  ["delete", "Allow media deletion"],
  ["upload", "Allow uploads"],
  ["accessExplicitContent", "Allow explicit content"],
  ["accessAllLibraries", "Allow all libraries"],
  ["accessAllTags", "Allow all tags"],
  ["selectedTagsNotAccessible", "Exclude selected tags instead of allowing them"],
] as const;
const split = (value: string) =>
  value
    .split(",")
    .map((value) => value.trim())
    .filter(Boolean);

export function AccountsScreen() {
  const { client, connection } = useAbs();
  const accounts = useQuery({
    queryKey: [connection.id, "administration", "accounts"],
    queryFn: ({ signal }) => client.get("/api/users", responseSchema, signal),
  });
  return (
    <div className="mx-auto flex max-w-3xl flex-col gap-6">
      <h1 className="text-2xl font-bold">Accounts</h1>
      <p className="text-muted">
        Account changes revoke existing sign-ins. Library and content restrictions apply to every client.
      </p>
      {accounts.isPending ? (
        <Spinner label="Loading accounts" />
      ) : accounts.isError ? (
        <Alert>{accounts.error.message}</Alert>
      ) : (
        <>
          <Section title="Create account">
            <AccountForm />
          </Section>
          {accounts.data.users.length ? (
            accounts.data.users.map((account) => (
              <Section key={account.id} title={account.username}>
                {account.type === "root" ? (
                  <p className="text-sm text-muted">
                    Owner account, protected from removal and role changes.
                  </p>
                ) : (
                  <AccountForm key={JSON.stringify(account)} account={account} />
                )}
              </Section>
            ))
          ) : (
            <EmptyState title="No accounts" />
          )}
        </>
      )}
    </div>
  );
}

function AccountForm({ account }: { account?: ManagedAccount }) {
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
    <form action={submit} className="flex flex-col gap-4">
      <fieldset disabled={pending} className="flex flex-col gap-4">
        <div className="grid gap-4 sm:grid-cols-2">
          <TextField
            name="username"
            label="Username"
            required
            minLength={3}
            maxLength={64}
            defaultValue={account?.username}
            autoComplete="off"
          />
          <TextField
            name="password"
            type="password"
            label={account ? "New password" : "Password"}
            required={!account}
            minLength={12}
            maxLength={512}
            autoComplete="new-password"
            help={account ? "Leave empty to keep the existing password" : "Use at least 12 characters"}
          />
          <SelectField name="type" label="Role" options={choices} defaultValue={account?.type ?? "user"} />
          <Toggle name="isActive" label="Account enabled" defaultChecked={account?.isActive ?? true} />
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
          label="Allowed library IDs"
          help="Separate IDs with commas. Used when all libraries are disabled."
          defaultValue={account?.librariesAccessible.join(", ") ?? ""}
        />
        <TextField
          name="tags"
          label="Selected tags"
          help="Separate tags with commas. Used when all tags are disabled."
          defaultValue={account?.itemTagsSelected.join(", ") ?? ""}
        />
        <div className="flex flex-wrap gap-3">
          <Button type="submit" name="operation" value="save" variant="primary">
            {pending ? "Saving…" : account ? "Save account" : "Create account"}
          </Button>
          {account ? (
            <>
              <Button type="submit" name="operation" value="revoke" formNoValidate>
                Revoke sign-ins
              </Button>
              <Button type="submit" name="operation" value="remove" formNoValidate>
                Remove account
              </Button>
            </>
          ) : null}
        </div>
      </fieldset>
      {result.kind !== "idle" ? (
        <Alert tone={result.kind === "success" ? "info" : "danger"}>{result.message}</Alert>
      ) : null}
    </form>
  );
}
