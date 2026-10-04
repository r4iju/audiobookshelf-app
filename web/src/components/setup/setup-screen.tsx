"use client";
import { ImportForm } from "@/components/setup/import-form";
import { SetupForm } from "@/components/setup/setup-form";
import { ButtonLink } from "@/components/ui/button";
import { useI18n } from "@/i18n/i18n";

export function SetupScreen({ ready }: { ready: boolean }) {
  const { t } = useI18n();
  return (
    <main className="mx-auto max-w-lg space-y-6 px-6 py-16">
      <p className="text-sm font-semibold text-accent">Leafwake</p>
      <h1 className="text-3xl font-bold">{t(ready ? "WebSetupReady" : "WebSetupCreateOwner")}</h1>
      {ready ? (
        <>
          <p>{t("WebSetupClosed")}</p>
          <ButtonLink href="/connect" variant="primary">
            {t("WebSignIn")}
          </ButtonLink>
        </>
      ) : (
        <>
          <p>{t("WebSetupLocalData")}</p>
          <SetupForm />
          <section className="space-y-4 border-t border-line pt-6">
            <h2 className="text-xl font-semibold">{t("WebSetupImport")}</h2>
            <ImportForm />
          </section>
        </>
      )}
    </main>
  );
}
