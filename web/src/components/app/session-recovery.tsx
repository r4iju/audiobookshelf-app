"use client";

import { Headphones } from "lucide-react";
import { ButtonLink } from "@/components/ui/button";
import { useI18n } from "@/i18n/i18n";
import type { Connection } from "@/lib/abs/connection";

/** A rejected session is recoverable without forgetting the account or its queued progress. */
export function SessionRecovery({ connection, next }: { connection: Connection; next: string }) {
  const { t } = useI18n();
  const href = `/connect?${new URLSearchParams({
    server: connection.serverUrl,
    username: connection.username,
    next,
  })}`;

  return (
    <main id="main" className="grid min-h-dvh place-items-center px-5 py-10">
      <section
        role="alert"
        aria-labelledby="session-recovery-title"
        className="flex w-full max-w-md flex-col items-center gap-5 rounded-[var(--radius-card)] border border-line bg-surface p-6 text-center shadow-sm sm:p-8"
      >
        <div
          aria-hidden
          className="grid size-14 place-items-center rounded-2xl bg-accent-strong text-accent-fg"
        >
          <Headphones className="size-7" />
        </div>
        <p className="text-sm font-semibold text-muted">{t("WebAppName")}</p>
        <h1 id="session-recovery-title" className="text-2xl font-bold">
          {t("WebSignIn")}
        </h1>
        <p className="text-sm leading-relaxed text-muted">{t("WebReauthRequired")}</p>
        <p className="max-w-full break-all text-sm">{connection.serverUrl}</p>
        <ButtonLink href={href} variant="primary" className="w-full">
          {t("WebSignIn")}
        </ButtonLink>
        <ButtonLink href="/connect" variant="ghost">
          {t("WebChangeServer")}
        </ButtonLink>
      </section>
    </main>
  );
}
