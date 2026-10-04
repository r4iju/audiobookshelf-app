"use client";
import { useActionState, useId } from "react";
import { type ImportResult, importAccounts } from "@/app/setup/actions";
import { Button, ButtonLink } from "@/components/ui/button";
import { TextField } from "@/components/ui/field";
import { FormFeedback } from "@/components/ui/form-feedback";
import { Alert } from "@/components/ui/status";
import { useI18n } from "@/i18n/i18n";
import { adminMessage } from "@/lib/abs/administration-messages";
import type { ImportReport } from "@/server/migration";

export function ImportForm() {
  const feedbackId = useId();
  const { t } = useI18n();
  const [result, submit, pending] = useActionState<ImportResult, FormData>(importAccounts, {
    status: "idle",
  });
  if (result.status === "complete")
    return (
      <div className="space-y-3">
        <p>{t("WebImportAccountCount", result.accountCount)}</p>
        <ButtonLink href="/connect" variant="primary">
          {t("WebSignIn")}
        </ButtonLink>
      </div>
    );
  return (
    <form
      aria-describedby={result.status === "error" ? feedbackId : undefined}
      action={submit}
      className="space-y-4"
    >
      <p className="text-sm text-muted">{t("WebAdminImportAccountsFromAClosedSQLiteSource")}</p>
      <TextField
        label={t("WebAdminSourceCopy")}
        name="sourcePath"
        defaultValue={result.status === "inspected" ? result.sourcePath : ""}
        required
        placeholder="/imports/absdatabase.sqlite"
        help={t("WebAdminUseAConsistentSQLiteCopyWithoutJournal")}
      />
      <TextField
        label={t("WebAdminSetupKey")}
        name="setupKey"
        type="password"
        required
        autoComplete="off"
        help={
          result.status === "inspected"
            ? t("WebAdminReEnterYourSetupKeyToConfirm")
            : t("WebAdminReadSetupKeyFromTheLeafwakeData")
        }
      />
      {result.status === "error" ? (
        <FormFeedback submission={result} id={feedbackId}>
          {adminMessage(result.message, t)}
        </FormFeedback>
      ) : null}
      {result.status === "inspected" ? (
        <>
          <ImportInventory report={result.report} />
          <input type="hidden" name="expectedDigest" value={result.report.digest} />
        </>
      ) : null}
      <div className="flex flex-wrap gap-3">
        <Button name="intent" value="inspect" type="submit" disabled={pending}>
          {pending ? t("WebAdminChecking") : t("WebAdminInspectSourceCopy")}
        </Button>
        {result.status === "inspected" && result.report.canImport ? (
          <Button name="intent" value="commit" type="submit" variant="primary" disabled={pending}>
            {t("WebAdminImportTheseAccounts")}
          </Button>
        ) : null}
      </div>
    </form>
  );
}
function ImportInventory({ report }: { report: ImportReport }) {
  const { t } = useI18n();
  return (
    <section
      className="space-y-3 rounded-xl border border-line p-4"
      aria-label={t("WebAdminImportInventory")}
    >
      <h3 className="font-semibold">{t("WebImportSupportedAccounts", report.accounts.length)}</h3>
      <p className="text-sm text-muted">{report.sourceSchema}</p>
      {report.notices.map((notice) => (
        <p key={notice} className="text-sm">
          {notice}
        </p>
      ))}
      {report.errors.length ? (
        <Alert>
          <ul>
            {report.errors.map((error) => (
              <li key={`${error.accountId ?? "source"}-${error.message}`}>
                {error.accountId ? `${error.accountId}: ` : ""}
                {adminMessage(error.message, t)}
              </li>
            ))}
          </ul>
        </Alert>
      ) : (
        <p>{t("WebAdminAccountInventoryPassed")}</p>
      )}
      <ul className="text-sm">
        {report.accounts.map((account) => (
          <li key={account.id}>
            {account.username} · {account.type} · {account.active ? "active" : "disabled"}
          </li>
        ))}
      </ul>
      <h4 className="font-semibold">{t("WebAdminRemainingSourceData")}</h4>
      {report.remainingData.length ? (
        <ul className="text-sm">
          {report.remainingData.map((table) => (
            <li key={table.table}>{t("WebImportRows", table.rows, table.table)}</li>
          ))}
        </ul>
      ) : (
        <p className="text-sm">{t("WebAdminNoOtherPopulatedSourceTables")}</p>
      )}
    </section>
  );
}
