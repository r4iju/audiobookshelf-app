"use client";
import { useActionState } from "react";
import { type ImportResult, importAccounts } from "@/app/setup/actions";
import { Button, ButtonLink } from "@/components/ui/button";
import { TextField } from "@/components/ui/field";
import { Alert } from "@/components/ui/status";
import type { ImportReport } from "@/server/migration";

export function ImportForm() {
  const [result, submit, pending] = useActionState<ImportResult, FormData>(importAccounts, {
    status: "idle",
  });
  if (result.status === "complete")
    return (
      <div className="space-y-3">
        <p>
          {result.accountCount} accounts imported. Sign in with your original owner password to continue the
          migration.
        </p>
        <ButtonLink href="/connect" variant="primary">
          Sign in
        </ButtonLink>
      </div>
    );
  return (
    <form action={submit} className="space-y-4">
      <p className="text-sm text-muted">
        Import accounts from a closed SQLite source copy mounted read-only. Your original data stays
        unchanged. Media, progress, lists and configuration must also pass their migration stages before
        cutover.
      </p>
      <TextField
        label="Source copy"
        name="sourcePath"
        defaultValue={result.status === "inspected" ? result.sourcePath : ""}
        required
        placeholder="/imports/absdatabase.sqlite"
        help="Use a consistent SQLite copy without journal sidecars in your configured import folder."
      />
      <TextField
        label="Setup key"
        name="setupKey"
        type="password"
        required
        autoComplete="off"
        help={
          result.status === "inspected"
            ? "Re-enter your setup key to confirm the account import."
            : "Read setup-key from the Leafwake data folder."
        }
      />
      {result.status === "error" ? <Alert>{result.message}</Alert> : null}
      {result.status === "inspected" ? (
        <>
          <ImportInventory report={result.report} />
          <input type="hidden" name="expectedDigest" value={result.report.digest} />
        </>
      ) : null}
      <div className="flex flex-wrap gap-3">
        <Button name="intent" value="inspect" type="submit" disabled={pending}>
          {pending ? "Checking…" : "Inspect source copy"}
        </Button>
        {result.status === "inspected" && result.report.canImport ? (
          <Button name="intent" value="commit" type="submit" variant="primary" disabled={pending}>
            Import these accounts
          </Button>
        ) : null}
      </div>
    </form>
  );
}
function ImportInventory({ report }: { report: ImportReport }) {
  return (
    <section className="space-y-3 rounded-xl border border-line p-4" aria-label="Import inventory">
      <h3 className="font-semibold">{report.accounts.length} supported accounts</h3>
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
                {error.message}
              </li>
            ))}
          </ul>
        </Alert>
      ) : (
        <p>Account inventory passed.</p>
      )}
      <ul className="text-sm">
        {report.accounts.map((account) => (
          <li key={account.id}>
            {account.username} · {account.type} · {account.active ? "active" : "disabled"}
          </li>
        ))}
      </ul>
      <h4 className="font-semibold">Remaining source data</h4>
      {report.remainingData.length ? (
        <ul className="text-sm">
          {report.remainingData.map((table) => (
            <li key={table.table}>
              {table.table}: {table.rows} rows
            </li>
          ))}
        </ul>
      ) : (
        <p className="text-sm">No other populated source tables.</p>
      )}
    </section>
  );
}
