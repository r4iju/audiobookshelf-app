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
import { type MediaImportReport, mediaImportReportSchema, mediaInspectSchema } from "@/lib/abs/imports";
import { useAbs } from "@/lib/session/store";

type Input = z.infer<typeof mediaInspectSchema>;
type Result =
  | { kind: "idle" }
  | { kind: "error"; message: string }
  | { kind: "inspected"; input: Input; report: MediaImportReport }
  | { kind: "completed"; items: number };
const completedSchema = z.object({ scope: z.literal("media"), report: mediaImportReportSchema });
export function MediaImportForm() {
  const feedbackId = useId();
  const { t } = useI18n();
  const { client, connection } = useAbs();
  const queries = useQueryClient();
  const [result, submit, pending] = useActionState<Result, FormData>(
    async (previous, form) => {
      try {
        const input = mediaInspectSchema.parse({
          sourcePath: form.get("sourcePath"),
          mappings: [{ from: form.get("originalPrefix"), to: form.get("mountedPrefix") }],
        });
        if (form.get("intent") === "commit") {
          if (
            previous.kind !== "inspected" ||
            !previous.report.canImport ||
            JSON.stringify(input) !== JSON.stringify(previous.input)
          )
            return {
              kind: "error",
              message: "Inspect the exact source and folder mapping before importing.",
            };
          const completed = await client.send(
            "POST",
            "/api/admin/migrations/media",
            { ...input, expectedDigest: previous.report.digest },
            completedSchema,
          );
          await queries.invalidateQueries({ queryKey: [connection.id] });
          return { kind: "completed", items: completed.report.counts.items };
        }
        return {
          kind: "inspected",
          input,
          report: await client.send(
            "POST",
            "/api/admin/migrations/media/inspect",
            input,
            mediaImportReportSchema,
          ),
        };
      } catch (error) {
        return {
          kind: "error",
          message: error instanceof Error ? error.message : "The source could not be inspected.",
        };
      }
    },
    { kind: "idle" },
  );
  if (result.kind === "completed") return <p role="status">{t("WebMediaImportComplete", result.items)}</p>;
  const input = result.kind === "inspected" ? result.input : null;
  return (
    <form
      aria-describedby={result.kind === "error" ? feedbackId : undefined}
      action={submit}
      className="space-y-4"
    >
      <p>{t("WebAdminUseTheSameClosedSQLiteCopyAs")}</p>
      <TextField
        name="sourcePath"
        label={t("WebAdminSourceDatabaseCopy")}
        required
        defaultValue={input?.sourcePath}
        placeholder="/imports/absdatabase.sqlite"
      />
      <TextField
        name="originalPrefix"
        label={t("WebAdminOriginalMediaFolder")}
        required
        defaultValue={input?.mappings[0]?.from}
        placeholder="/original/audiobooks"
      />
      <TextField
        name="mountedPrefix"
        label={t("WebAdminMountedMediaFolder")}
        required
        defaultValue={input?.mappings[0]?.to}
        placeholder="/media/audiobooks"
      />
      {result.kind === "error" ? (
        <FormFeedback submission={result} id={feedbackId}>
          {adminMessage(result.message, t)}
        </FormFeedback>
      ) : null}
      {result.kind === "inspected" ? (
        <div className="space-y-3" role="status">
          <p>
            {t(
              "WebMediaCounts",
              result.report.counts.libraries,
              result.report.counts.items,
              result.report.counts.files,
              result.report.counts.progress,
              result.report.counts.bookmarks,
              result.report.counts.listeningSeconds,
            )}
          </p>
          {result.report.errors.length ? (
            <Alert>
              <ul>
                {result.report.errors.map((error) => (
                  <li key={JSON.stringify(error)}>
                    {error.table}: {adminMessage(error.message, t)}
                  </li>
                ))}
              </ul>
            </Alert>
          ) : null}
          {result.report.remainingData.length ? (
            <div>
              <h3 className="font-semibold">{t("WebAdminDataRequiringRemainingMigrationStages")}</h3>
              <ul>
                {result.report.remainingData.map((row) => (
                  <li key={row.table}>
                    {row.table}: {row.rows} records
                    {row.recordIds?.length ? (
                      <span className="block break-all text-xs">{row.recordIds.join(", ")}</span>
                    ) : null}
                  </li>
                ))}
              </ul>
            </div>
          ) : (
            <p>{t("WebAdminNoUnmappedRecordsWereFoundInThis")}</p>
          )}
          {result.report.notices.map((notice) => (
            <p key={notice} className="text-sm text-muted">
              {notice}
            </p>
          ))}
          <p>{t("WebAdminFullCutoverIsNotYetApprovedBy")}</p>
        </div>
      ) : null}
      <div className="flex flex-wrap gap-3">
        <Button type="submit" name="intent" value="inspect" disabled={pending}>
          {t("WebAdminInspectSourceCopy")}
        </Button>
        {result.kind === "inspected" && result.report.canImport ? (
          <Button type="submit" name="intent" value="commit" disabled={pending} variant="secondary">
            {t("WebAdminImportMediaAndHistory")}
          </Button>
        ) : null}
      </div>
    </form>
  );
}
