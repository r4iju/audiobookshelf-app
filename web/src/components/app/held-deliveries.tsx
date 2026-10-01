"use client";

import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { InlineError } from "@/components/app/inline-error";
import { Button } from "@/components/ui/button";
import { Alert } from "@/components/ui/status";
import { useI18n } from "@/i18n/i18n";
import { keys } from "@/lib/abs/queries";
import {
  confirmServerRestarted,
  flushReports,
  heldDeliveries,
  requestServerRestart,
  serverOrigin,
} from "@/lib/progress/sync";
import { useAbs, useSessionStore } from "@/lib/session/store";

/** Offers the restart that alone releases deliveries held by a delete that may still be running on the server. */
export function HeldDeliveries() {
  const { client, connection } = useAbs();
  const { t } = useI18n();
  const queryClient = useQueryClient();
  const key = keys.heldDeliveries(connection.id);
  const state = useQuery({ queryKey: key, queryFn: () => heldDeliveries(client), refetchInterval: 15_000 });
  const refresh = () => queryClient.invalidateQueries({ queryKey: key });
  const request = useMutation({ mutationFn: () => requestServerRestart(client), onSettled: refresh });
  const confirm = useMutation({
    mutationFn: async () => {
      await confirmServerRestarted(client);
      await flushReports(client, useSessionStore.getState().requireReauth);
    },
    onSettled: refresh,
  });

  if (!state.data || (state.data.held === 0 && !state.data.restart)) return null;
  const { restart } = state.data;
  const asked = restart !== null && restart !== "unreadable";
  const step = asked ? confirm : request;
  const message =
    restart === null
      ? t("WebHeldDeliveries", serverOrigin(client))
      : restart === "unreadable"
        ? t("WebHeldRestartUnreadable", serverOrigin(client))
        : t("WebHeldRestartRequested", restart.serverOrigin);
  return (
    <Alert
      action={
        <Button size="sm" variant="primary" disabled={step.isPending} onClick={() => step.mutate()}>
          {t(asked ? "WebServerRestarted" : "WebRestartTheServer")}
        </Button>
      }
    >
      <p>{message}</p>
      <InlineError error={request.error ?? confirm.error} />
    </Alert>
  );
}
