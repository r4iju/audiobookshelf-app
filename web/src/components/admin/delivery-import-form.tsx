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
  type DeliveryImportReport,
  deliveryImportInput,
  deliveryImportReportSchema,
} from "@/lib/abs/imports";
import { useAbs } from "@/lib/session/store";

type Result =
  | { kind: "idle" }
  | { kind: "error"; message: string }
  | { kind: "inspected"; report: DeliveryImportReport; serverAddress: string }
  | { kind: "completed"; report: DeliveryImportReport };
export function DeliveryImportForm() {
  const feedbackId = useId();
  const { t } = useI18n();
  const { client, connection } = useAbs();
  const queries = useQueryClient();
  const [result, submit, pending] = useActionState<Result, FormData>(
    async (previous, form) => {
      try {
        const input = deliveryImportInput.parse({
          digest: form.get("digest"),
          serverAddress: form.get("serverAddress"),
        });
        if (form.get("intent") === "commit") {
          if (
            previous.kind !== "inspected" ||
            previous.report.digest !== input.digest ||
            previous.serverAddress !== input.serverAddress ||
            !previous.report.canImport
          )
            return {
              kind: "error",
              message: "Inspect this source before importing feeds and delivery settings.",
            };
          const completed = await client.send(
            "POST",
            "/api/admin/migrations/delivery",
            input,
            z.object({ report: deliveryImportReportSchema }),
          );
          await queries.invalidateQueries({ queryKey: [connection.id] });
          return { kind: "completed", report: completed.report };
        }
        return {
          kind: "inspected",
          serverAddress: input.serverAddress,
          report: await client.send(
            "POST",
            "/api/admin/migrations/delivery/inspect",
            input,
            deliveryImportReportSchema,
          ),
        };
      } catch (error) {
        return { kind: "error", message: error instanceof Error ? error.message : "Delivery import failed." };
      }
    },
    { kind: "idle" },
  );
  const report = result.kind === "inspected" || result.kind === "completed" ? result.report : null;
  return (
    <form
      aria-describedby={result.kind === "error" ? feedbackId : undefined}
      action={submit}
      className="space-y-4"
    >
      <p>{t("WebAdminUseTheSourceDigestFromACompleted")}</p>
      <TextField
        name="serverAddress"
        label={t("WebAdminReplacementPublicServerURL")}
        required
        defaultValue={result.kind === "inspected" ? result.serverAddress : ""}
      />
      <TextField
        name="digest"
        label={t("WebAdminSourceDigest")}
        required
        defaultValue={report?.digest ?? ""}
      />
      {result.kind === "error" ? (
        <FormFeedback submission={result} id={feedbackId}>
          {adminMessage(result.message, t)}
        </FormFeedback>
      ) : null}
      {report ? (
        <div className="space-y-2">
          <p role="status">
            {t(
              "WebDeliveryCounts",
              result.kind === "completed" ? t("WebAdminImported") : t("WebAdminFound"),
              report.counts.feeds,
              report.counts.episodes,
              report.counts.devices,
            )}
          </p>
          {report.notices.map((notice) => (
            <p key={notice} className="text-sm text-muted">
              {notice}
            </p>
          ))}
          {report.errors.map((error) => (
            <Alert key={`${error.table}:${error.id}:${error.message}`}>
              {error.table} {error.id}: {adminMessage(error.message, t)}
            </Alert>
          ))}
          {report.unsupported.length ? (
            <ul aria-label={t("WebAdminArchivedDeliveryFields")}>
              {report.unsupported.map((entry) => (
                <li key={`${entry.table}:${entry.id}`}>
                  {entry.table} {entry.id}: {entry.fields.join(", ")}
                </li>
              ))}
            </ul>
          ) : null}
        </div>
      ) : null}
      {result.kind === "completed" ? null : (
        <div className="flex flex-wrap gap-2">
          <Button type="submit" name="intent" value="inspect" disabled={pending}>
            {t("WebAdminInspectFeedsAndDelivery")}
          </Button>
          {result.kind === "inspected" && result.report.canImport ? (
            <Button type="submit" name="intent" value="commit" disabled={pending} variant="primary">
              {t("WebAdminImportFeedsAndDelivery")}
            </Button>
          ) : null}
        </div>
      )}
    </form>
  );
}
