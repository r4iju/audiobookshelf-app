"use client";

import { useRouter } from "next/navigation";
import { useEffect } from "react";
import { ButtonLink } from "@/components/ui/button";
import { Alert, EmptyState, Spinner } from "@/components/ui/status";
import { useI18n } from "@/i18n/i18n";
import { isAdmin } from "@/lib/abs/permissions";
import { useLibraries, useMe } from "@/lib/abs/queries";
import * as registry from "@/lib/session/registry";
import { useSession } from "@/lib/session/store";
import { errorMessage } from "./errors";
import { SessionRecovery } from "./session-recovery";

export function RootRedirect() {
  const session = useSession();
  const { t } = useI18n();
  const router = useRouter();

  // External system: routing; a signed-out browser goes to the connect screen.
  useEffect(() => {
    if (session.phase === "signed-out") router.replace("/connect");
  }, [session.phase, router]);

  if (session.phase !== "signed-in") return <Spinner label={t("MessageLoading")} />;
  if (session.reauthRequired) return <SessionRecovery connection={session.connection} next="/" />;
  return <LibraryRedirect connectionId={session.connection.id} />;
}

function LibraryRedirect({ connectionId }: { connectionId: string }) {
  const { t } = useI18n();
  const router = useRouter();
  const libraries = useLibraries();
  const admin = isAdmin(useMe().data);
  const remembered = registry.lastLibraryId(connectionId);
  const target = libraries.data?.find((library) => library.id === remembered) ?? libraries.data?.[0];

  // External system: routing to the last library once the server has listed what this account may open.
  useEffect(() => {
    if (target) router.replace(`/library/${target.id}`);
  }, [target, router]);

  if (libraries.isError) return <Alert>{errorMessage(t, libraries.error)}</Alert>;
  if (libraries.isSuccess && !target)
    return (
      <EmptyState title={t("WebNoLibraries")}>
        {admin ? (
          <>
            <ButtonLink href="/admin/libraries">Create library</ButtonLink>
            <ButtonLink href="/admin/accounts">Manage accounts</ButtonLink>
          </>
        ) : null}
      </EmptyState>
    );
  return <Spinner label={t("MessageLoading")} />;
}
