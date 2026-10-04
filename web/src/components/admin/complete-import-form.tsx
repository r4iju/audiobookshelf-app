"use client";
import { useQueryClient } from "@tanstack/react-query";
import { useActionState, useId } from "react";
import { z } from "zod";
import { Button } from "@/components/ui/button";
import { TextField } from "@/components/ui/field";
import { FormFeedback } from "@/components/ui/form-feedback";
import { Alert } from "@/components/ui/status";
import { useI18n } from "@/i18n/i18n";
import { adminMessage } from "@/lib/abs/administration-messages";
import {
  type CompleteImportInput,
  type CompleteImportReport,
  completeImportInput,
  completeImportReport,
} from "@/lib/abs/complete-import";
import { useAbs } from "@/lib/session/store";

const completion = z.object({ id: z.string(), rollbackBackupId: z.string(), report: completeImportReport });
type Result =
  | { kind: "idle" }
  | { kind: "error"; message: string }
  | { kind: "inspected"; input: CompleteImportInput; report: CompleteImportReport }
  | { kind: "completed"; input: CompleteImportInput; report: CompleteImportReport; rollbackBackupId: string };
export function CompleteImportForm() {
  const { t } = useI18n(),
    { client, connection } = useAbs(),
    queries = useQueryClient(),
    feedbackId = useId();
  const [result, submit, pending] = useActionState<Result, FormData>(
    async (_prior, form) => {
      try {
        const from = z.string().parse(form.get("coverFrom")),
          to = z.string().parse(form.get("coverTo"));
        const input = completeImportInput.parse({
          digest: form.get("digest"),
          sourcePath: form.get("sourcePath"),
          publicUrl: form.get("publicUrl"),
          coverMappings: from || to ? [{ from, to }] : [],
          redirectUris: z
            .string()
            .parse(form.get("callbacks"))
            .split("\n")
            .map((value) => value.trim())
            .filter(Boolean),
        });
        if (form.get("intent") === "commit") {
          const completed = await client.send("POST", "/api/admin/migrations/complete", input, completion);
          await queries.invalidateQueries({ queryKey: [connection.id] });
          return {
            kind: "completed",
            input,
            report: completed.report,
            rollbackBackupId: completed.rollbackBackupId,
          };
        }
        return {
          kind: "inspected",
          input,
          report: await client.send(
            "POST",
            "/api/admin/migrations/complete/inspect",
            input,
            completeImportReport,
          ),
        };
      } catch (error) {
        return {
          kind: "error",
          message:
            error instanceof z.ZodError
              ? "Check the migration fields and retry."
              : error instanceof Error
                ? error.message
                : "Complete migration failed.",
        };
      }
    },
    { kind: "idle" },
  );
  const input = result.kind === "inspected" || result.kind === "completed" ? result.input : null,
    report = result.kind === "inspected" || result.kind === "completed" ? result.report : null;
  return (
    <form
      action={submit}
      aria-describedby={result.kind === "error" ? feedbackId : undefined}
      className="space-y-4"
    >
      <p className="text-sm text-muted">{t("WebCompleteImportHelp")}</p>
      <TextField
        name="digest"
        label={t("WebAdminSourceDigest")}
        required
        defaultValue={input?.digest ?? ""}
      />
      <TextField
        name="sourcePath"
        label={t("WebAdminSourceDatabaseCopy")}
        required
        defaultValue={input?.sourcePath ?? ""}
      />
      <TextField
        name="publicUrl"
        label={t("WebAdminReplacementPublicServerURL")}
        required
        defaultValue={input?.publicUrl ?? connection.serverUrl}
      />
      <TextField
        name="coverFrom"
        label={t("WebOriginalCoverRoot")}
        defaultValue={input?.coverMappings[0]?.from ?? ""}
        help={t("WebCoverMappingHelp")}
      />
      <TextField
        name="coverTo"
        label={t("WebMountedCoverRoot")}
        defaultValue={input?.coverMappings[0]?.to ?? ""}
      />
      <label className="flex flex-col gap-2 text-sm font-medium">
        {t("WebMigrationCallbacks")}
        <textarea
          name="callbacks"
          className="min-h-24 min-w-0 rounded-xl border border-line bg-surface p-3 font-normal"
          defaultValue={
            input?.redirectUris.join("\n") ??
            `${connection.serverUrl}/oauth\naudiobookshelf-native-preview://oauth`
          }
        />
      </label>
      {result.kind === "error" ? (
        <FormFeedback submission={result} id={feedbackId}>
          {adminMessage(result.message, t)}
        </FormFeedback>
      ) : null}
      {report ? (
        <div className="space-y-3">
          <p role="status">
            {t(
              "WebCompleteCounts",
              report.counts.openIdIdentities,
              report.counts.covers,
              report.counts.configuration,
              report.counts.sourceRows,
            )}
          </p>
          {report.errors.map((error) => (
            <Alert key={`${error.table}:${error.id}:${error.message}`}>
              {error.table} {error.id}: {adminMessage(error.message, t)}
            </Alert>
          ))}
          {report.unsupported.length ? (
            <Alert>
              <p>{t("WebCutoverBlocked")}</p>
              <ul className="list-disc ps-5">
                {report.unsupported.map((entry) => (
                  <li key={`${entry.table}:${entry.id}:${entry.fields.join(",")}:${entry.reason}`}>
                    {entry.table} {entry.id}: {entry.fields.join(", ")} · {entry.reason}
                  </li>
                ))}
              </ul>
            </Alert>
          ) : null}
          <details>
            <summary className="cursor-pointer font-medium">{t("WebSourceInventory")}</summary>
            <ul className="space-y-2 break-words">
              {report.inventory.map((entry) => (
                <li key={entry.table}>
                  {entry.table} · {entry.rows} · {entry.disposition}
                  <ul className="ps-4 text-sm">
                    {entry.fields.map((field) => (
                      <li key={field.name}>
                        {field.name} · {field.disposition}
                      </li>
                    ))}
                  </ul>
                </li>
              ))}
            </ul>
          </details>
          {report.notices.map((notice) => (
            <p key={notice} className="text-sm text-muted">
              {notice}
            </p>
          ))}
        </div>
      ) : null}
      {result.kind === "completed" ? (
        <Alert tone="info">{t("WebCompleteMigrationSaved", result.rollbackBackupId)}</Alert>
      ) : (
        <div className="flex flex-wrap gap-2">
          <Button name="intent" value="inspect" type="submit" disabled={pending}>
            {pending ? t("WebAdminChecking") : t("WebInspectCompleteMigration")}
          </Button>
          {report?.canCutover ? (
            <Button name="intent" value="commit" type="submit" variant="primary" disabled={pending}>
              {t("WebCompleteMigrationCommit")}
            </Button>
          ) : null}
        </div>
      )}
    </form>
  );
}
