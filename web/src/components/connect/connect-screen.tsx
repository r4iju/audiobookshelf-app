"use client";

import { Server, Trash2 } from "lucide-react";
import { useRouter } from "next/navigation";
import { useActionState, useEffect, useState } from "react";
import { Button } from "@/components/ui/button";
import { TextField } from "@/components/ui/field";
import { Alert } from "@/components/ui/status";
import { type Translate, useI18n } from "@/i18n/i18n";
import {
  isSameOrigin,
  type LoginFailure,
  type ProbeFailure,
  passwordLogin,
  probeServer,
  startOpenId,
} from "@/lib/abs/auth";
import type { ServerStatus } from "@/lib/abs/schemas";
import * as registry from "@/lib/session/registry";
import { useSession, useSessionStore } from "@/lib/session/store";
import { savePendingOpenId } from "./openid-pending";

type Step =
  | { step: "address"; error: ProbeFailure | null; attempted: string }
  | {
      step: "credentials";
      serverUrl: string;
      status: ServerStatus;
      error: LoginFailure | null;
      errorStatus?: number;
      username: string;
    };

function probeMessage(t: Translate, failure: ProbeFailure, address: string) {
  switch (failure) {
    case "invalid-address":
      return t("WebErrorInvalidAddress");
    case "unreachable":
      return t("WebErrorUnreachable", address);
    case "not-audiobookshelf":
      return t("WebErrorNotAudiobookshelf");
    case "not-initialized":
      return t("WebErrorNotInitialized");
  }
}

function loginMessage(t: Translate, failure: LoginFailure, status?: number) {
  switch (failure) {
    case "invalid-credentials":
      return t("WebErrorInvalidCredentials");
    case "rate-limited":
      return t("WebErrorRateLimited");
    case "unreachable":
      return t("WebErrorCors");
    case "server-error":
      return t("WebErrorServer", status ?? "?");
    case "invalid-response":
      return t("WebErrorNotAudiobookshelf");
  }
}

export function ConnectScreen({
  initialServer,
  initialUsername,
}: {
  initialServer: string;
  initialUsername: string;
}) {
  const { t } = useI18n();
  const router = useRouter();
  const signIn = useSessionStore((state) => state.signIn);
  const switchTo = useSessionStore((state) => state.switchTo);
  // Stays disabled until hydration has restored saved servers, so an early click cannot submit a dead form.
  const restoring = useSession().phase === "restoring";
  const [saved, setSaved] = useState<registry.SavedConnection[]>([]);

  // External system: saved servers are read from this browser's storage after mount.
  useEffect(() => {
    setSaved(registry.loadRegistry().connections);
  }, []);

  const [state, submit, pending] = useActionState(
    async (previous: Step, form: FormData): Promise<Step> => {
      if (form.get("intent") === "change-server") return { step: "address", error: null, attempted: "" };
      if (previous.step === "address") {
        const address = String(form.get("server") ?? "");
        const result = await probeServer(address);
        if (!result.ok)
          return { step: "address", error: result.reason, attempted: result.serverUrl ?? address };
        return {
          step: "credentials",
          serverUrl: result.serverUrl,
          status: result.status,
          error: null,
          username: initialUsername,
        };
      }
      if (form.get("intent") === "openid") {
        const redirectUri = `${location.origin}${process.env.NEXT_PUBLIC_BASE_PATH ?? ""}/oauth`;
        const { url, pending: openId } = await startOpenId(previous.serverUrl, redirectUri);
        savePendingOpenId(openId);
        location.assign(url);
        return previous;
      }
      const username = String(form.get("username") ?? "");
      const result = await passwordLogin(
        previous.serverUrl,
        username,
        String(form.get("password") ?? ""),
        previous.status.serverVersion,
      );
      // React resets the form after an action; the username survives through its default value.
      if (!result.ok) return { ...previous, error: result.reason, errorStatus: result.status, username };
      signIn(result.connection);
      router.replace("/");
      return previous;
    },
    { step: "address", error: null, attempted: "" },
  );

  const reusable = saved.filter((entry) => entry.auth);
  const signedOut = saved.filter((entry) => !entry.auth);

  return (
    <main
      id="main"
      className="mx-auto flex min-h-dvh w-full max-w-md flex-col justify-center gap-6 px-5 py-10"
    >
      <header className="flex flex-col items-center gap-3 text-center">
        <div
          aria-hidden
          className="grid size-14 place-items-center rounded-2xl bg-accent-strong text-accent-fg"
        >
          <Server className="size-7" />
        </div>
        <h1 className="text-2xl font-bold">
          {state.step === "address"
            ? t("ButtonConnectToServer")
            : t("WebSignInTo", new URL(state.serverUrl).host)}
        </h1>
      </header>

      <form action={submit} className="rounded-[var(--radius-card)] bg-surface p-5 shadow-sm">
        <fieldset disabled={restoring || pending} className="flex flex-col gap-4">
          {state.step === "address" ? (
            <>
              <TextField
                label={t("LabelServerAddress")}
                name="server"
                type="url"
                inputMode="url"
                autoComplete="url"
                required
                defaultValue={state.attempted || initialServer}
                placeholder="https://"
                help={t("WebServerAddressHelp")}
              />
              {state.error ? <Alert>{probeMessage(t, state.error, state.attempted)}</Alert> : null}
              <Button type="submit" variant="primary">
                {t("WebContinue")}
              </Button>
            </>
          ) : (
            <>
              <p className="break-all text-sm text-muted">
                {state.serverUrl}
                {state.status.serverVersion
                  ? ` · ${t("WebServerVersion", state.status.serverVersion)}`
                  : null}
              </p>
              {state.status.authFormData?.authLoginCustomMessage ? (
                <p className="text-sm">{state.status.authFormData.authLoginCustomMessage}</p>
              ) : null}
              {state.status.authMethods.includes("local") ? (
                <>
                  <TextField
                    label={t("LabelUsername")}
                    name="username"
                    autoComplete="username"
                    required
                    defaultValue={state.username}
                    autoFocus
                  />
                  <TextField
                    label={t("LabelPassword")}
                    name="password"
                    type="password"
                    autoComplete="current-password"
                  />
                  {state.error ? <Alert>{loginMessage(t, state.error, state.errorStatus)}</Alert> : null}
                  <Button type="submit" variant="primary">
                    {t("WebSignIn")}
                  </Button>
                </>
              ) : null}
              {state.status.authMethods.includes("openid") ? (
                isSameOrigin(state.serverUrl) ? (
                  <Button
                    type="submit"
                    name="intent"
                    value="openid"
                    variant={state.status.authMethods.includes("local") ? "secondary" : "primary"}
                    formNoValidate
                  >
                    {state.status.authFormData?.authOpenIDButtonText || t("WebSignInWithOpenId")}
                  </Button>
                ) : (
                  <Alert tone="info">{t("WebOpenIdUnavailable")}</Alert>
                )
              ) : null}
              <Button type="submit" name="intent" value="change-server" variant="ghost" formNoValidate>
                {t("WebChangeServer")}
              </Button>
            </>
          )}
        </fieldset>
      </form>

      {reusable.length + signedOut.length > 0 && state.step === "address" ? (
        <section aria-labelledby="saved-servers" className="flex flex-col gap-2">
          <h2 id="saved-servers" className="text-sm font-semibold text-muted">
            {t("WebSavedServers")}
          </h2>
          <ul className="flex flex-col gap-2">
            {saved.map((entry) => (
              <li key={entry.id} className="flex items-center gap-2 rounded-xl bg-surface p-3">
                <div className="min-w-0 flex-1">
                  <p className="truncate font-medium">{entry.username}</p>
                  <p className="truncate text-xs text-muted">{entry.serverUrl}</p>
                </div>
                {entry.auth ? (
                  <Button
                    size="sm"
                    variant="primary"
                    onClick={() => {
                      switchTo(entry.id);
                      router.replace("/");
                    }}
                  >
                    {t("ButtonConnect")}
                  </Button>
                ) : (
                  <Button
                    size="sm"
                    onClick={() =>
                      router.replace(
                        `/connect?${new URLSearchParams({ server: entry.serverUrl, username: entry.username })}`,
                      )
                    }
                  >
                    {t("WebSignIn")}
                  </Button>
                )}
                <Button
                  size="icon"
                  variant="ghost"
                  aria-label={`${t("ButtonRemove")} ${entry.username} · ${entry.serverUrl}`}
                  onClick={() => setSaved(registry.forget(entry.id).connections)}
                >
                  <Trash2 aria-hidden className="size-4" />
                </Button>
              </li>
            ))}
          </ul>
        </section>
      ) : null}
      <p className="text-center text-xs text-muted">{t("WebLocalStorageWarning")}</p>
    </main>
  );
}
