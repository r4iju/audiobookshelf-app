"use client";

import { useQueryClient } from "@tanstack/react-query";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { useEffect, useState } from "react";
import { buttonClass } from "@/components/ui/button";
import { Alert, Spinner } from "@/components/ui/status";
import { type Translate, useI18n } from "@/i18n/i18n";
import { completeOpenId } from "@/lib/abs/auth";
import { keys } from "@/lib/abs/queries";
import { useSessionStore } from "@/lib/session/store";
import { takePendingOpenId } from "./openid-pending";

type Failure =
  | Extract<Awaited<ReturnType<typeof completeOpenId>>, { ok: false }>
  | { ok: false; reason: "not-started" };

async function exchange(search: string) {
  const pending = takePendingOpenId();
  if (!pending) return { failure: { ok: false, reason: "not-started" } satisfies Failure, serverUrl: null };
  const outcome = await completeOpenId(pending, new URLSearchParams(search));
  if (!outcome.ok) return { failure: outcome, serverUrl: pending.serverUrl };
  return { connection: outcome.connection, returnTo: pending.returnTo };
}

// A code can be exchanged once, and React may start an effect twice; both starts share one exchange.
let current: { search: string; result: ReturnType<typeof exchange> } | null = null;
function exchangeOnce(search: string) {
  if (current?.search !== search) current = { search, result: exchange(search) };
  return current.result;
}

function reason(t: Translate, failure: Failure) {
  switch (failure.reason) {
    case "not-started":
      return t("WebOpenIdNotStarted");
    case "state-mismatch":
      return t("WebOpenIdStateMismatch");
    case "provider-error":
      return t("WebOpenIdRefused", failure.detail ?? "?");
    case "rejected":
      return t("WebOpenIdServerRefused", failure.detail ?? "?");
    case "invalid-credentials":
      return t("WebOpenIdRejected");
    case "rate-limited":
      return t("WebOpenIdRateLimited");
    case "unreachable":
      return t("WebOpenIdUnreachable");
    case "server-error":
    case "invalid-response":
      return t("WebOpenIdServerError", failure.status ?? "?");
  }
}

export function OpenIdReturn() {
  const { t } = useI18n();
  const router = useRouter();
  const queryClient = useQueryClient();
  const signIn = useSessionStore((state) => state.signIn);
  const [failed, setFailed] = useState<{ failure: Failure; serverUrl: string | null } | null>(null);

  // External system: the server, which trades the provider's code for this account's tokens.
  useEffect(() => {
    let live = true;
    void exchangeOnce(location.search).then((result) => {
      if (!live) return;
      if (result.failure) {
        setFailed({ failure: result.failure, serverUrl: result.serverUrl });
        return;
      }
      queryClient.removeQueries({ queryKey: keys.all(result.connection.id) });
      signIn(result.connection);
      // The code and state leave the address bar and history with this replace.
      router.replace(result.returnTo);
    });
    return () => {
      live = false;
    };
  }, [queryClient, router, signIn]);

  return (
    <main
      id="main"
      className="mx-auto flex min-h-dvh w-full max-w-md flex-col justify-center gap-4 px-5 py-10"
    >
      {failed ? (
        <>
          <Alert>{t("WebOpenIdFailed", reason(t, failed.failure))}</Alert>
          <Link
            href={failed.serverUrl ? `/connect?server=${encodeURIComponent(failed.serverUrl)}` : "/connect"}
            className={buttonClass("primary")}
          >
            {t("WebTryAgain")}
          </Link>
        </>
      ) : (
        <Spinner label={t("WebOpenIdCompleting")} />
      )}
    </main>
  );
}
