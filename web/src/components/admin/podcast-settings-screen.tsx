"use client";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import { useActionState, useId } from "react";
import { z } from "zod";
import { Button, ButtonLink } from "@/components/ui/button";
import { TextField, Toggle } from "@/components/ui/field";
import { FormFeedback } from "@/components/ui/form-feedback";
import { Alert, Spinner } from "@/components/ui/status";
import { useI18n } from "@/i18n/i18n";
import { adminMessage } from "@/lib/abs/administration-messages";
import { useAbs } from "@/lib/session/store";

const schema = z.object({
  discoveryEnabled: z.boolean(),
  providerUrl: z.string(),
  country: z.string(),
  updateIntervalMinutes: z.number(),
  maxQueue: z.number(),
  maxConcurrent: z.number(),
  maxEpisodeBytes: z.number(),
  downloadTimeoutSeconds: z.number(),
  retentionEpisodes: z.number(),
});
type Result = { kind: "idle" } | { kind: "saved" } | { kind: "error"; message: string };
export function PodcastSettingsScreen() {
  const { t } = useI18n();
  const { client, connection } = useAbs();
  const queries = useQueryClient();
  const settings = useQuery({
    queryKey: [connection.id, "podcast-settings"],
    queryFn: ({ signal }) => client.get("/api/admin/podcasts/settings", schema, signal),
  });
  if (settings.isPending) return <Spinner label={t("WebAdminLoadingPodcastSettings")} />;
  if (settings.isError) return <Alert>{adminMessage(settings.error.message, t)}</Alert>;
  return (
    <div className="mx-auto flex max-w-3xl flex-col gap-6">
      <h1 className="text-2xl font-bold">{t("WebAdminPodcastSettings")}</h1>
      <p>{t("WebAdminControlDiscoveryAutomaticFeedChecksAndServer")}</p>
      <SettingsForm
        key={connection.id}
        initial={settings.data}
        save={async (value) => {
          await client.send("PATCH", "/api/admin/podcasts/settings", value, schema);
          await queries.invalidateQueries({ queryKey: [connection.id, "podcast-settings"] });
        }}
      />
      <Subscriptions />
    </div>
  );
}
function SettingsForm({
  initial,
  save,
}: {
  initial: z.infer<typeof schema>;
  save: (value: z.infer<typeof schema>) => Promise<void>;
}) {
  const feedbackId = useId();
  const { t } = useI18n();
  const [result, action, pending] = useActionState<Result, FormData>(
    async (_prior, form) => {
      const value = schema.safeParse({
        ...Object.fromEntries(form),
        discoveryEnabled: form.get("discoveryEnabled") === "on",
        ...Object.fromEntries(
          [
            "updateIntervalMinutes",
            "maxQueue",
            "maxConcurrent",
            "maxEpisodeBytes",
            "downloadTimeoutSeconds",
            "retentionEpisodes",
          ].map((key) => [key, Number(form.get(key))]),
        ),
      });
      if (!value.success) return { kind: "error", message: "Complete every setting with a valid value." };
      try {
        await save(value.data);
        return { kind: "saved" };
      } catch (error) {
        return {
          kind: "error",
          message: error instanceof Error ? error.message : "Settings could not be saved",
        };
      }
    },
    { kind: "idle" },
  );
  return (
    <form
      aria-describedby={result.kind === "error" ? feedbackId : undefined}
      action={action}
      className="flex flex-col gap-4 rounded-xl bg-surface p-5"
    >
      <Toggle
        name="discoveryEnabled"
        label={t("WebAdminEnablePodcastDiscovery")}
        defaultChecked={initial.discoveryEnabled}
      />
      <TextField
        name="providerUrl"
        label={t("WebAdminDiscoveryProviderURL")}
        defaultValue={initial.providerUrl}
        required
      />
      <TextField
        name="country"
        label={t("WebAdminCountryCode")}
        defaultValue={initial.country}
        required
        maxLength={2}
      />
      {[
        { name: "updateIntervalMinutes", label: t("WebAdminFeedCheckIntervalMinutes"), min: 1, max: 10080 },
        { name: "maxQueue", label: t("WebAdminMaximumOutstandingDownloads"), min: 1, max: 128 },
        { name: "maxConcurrent", label: t("WebAdminConcurrentDownloads"), min: 1, max: 2 },
        {
          name: "maxEpisodeBytes",
          label: t("WebAdminMaximumEpisodeSizeBytes"),
          min: 1048576,
          max: 1073741824,
        },
        { name: "downloadTimeoutSeconds", label: t("WebAdminDownloadTimeoutSeconds"), min: 30, max: 3600 },
        { name: "retentionEpisodes", label: t("WebAdminEpisodesToKeep0KeepsAll"), min: 0, max: 1000 },
      ].map((field) => (
        <TextField
          key={field.name}
          name={field.name}
          label={field.label}
          type="number"
          min={field.min}
          max={field.max}
          required
          defaultValue={String(Object.entries(initial).find(([key]) => key === field.name)?.[1] ?? "")}
        />
      ))}
      {result.kind === "error" ? (
        <FormFeedback submission={result} id={feedbackId}>
          {adminMessage(result.message, t)}
        </FormFeedback>
      ) : result.kind === "saved" ? (
        <p role="status">{t("WebAdminSettingsSaved")}</p>
      ) : null}
      <Button type="submit" variant="primary" disabled={pending}>
        {pending ? t("WebAdminSaving") : t("WebAdminSaveSettings")}
      </Button>
    </form>
  );
}

const subscriptionSchema = z.object({
  id: z.string(),
  title: z.string(),
  autoDownloadEpisodes: z.boolean(),
  nextCheckAt: z.number().nullable(),
  lastCheckedAt: z.number().nullable(),
  leaseUntil: z.number().nullable(),
  lastError: z.string().nullable(),
});
function Subscriptions() {
  const { t } = useI18n();
  const { connection, client } = useAbs();
  const subscriptions = useQuery({
    queryKey: [connection.id, "podcast-subscriptions"],
    queryFn: ({ signal }) =>
      client.get("/api/admin/podcasts/subscriptions", z.array(subscriptionSchema), signal),
    refetchInterval: 10000,
  });
  return (
    <section className="flex flex-col gap-4">
      <h2 className="text-xl font-semibold">{t("WebAdminSubscriptions")}</h2>
      {subscriptions.isPending ? (
        <Spinner label={t("WebAdminLoadingSubscriptions")} />
      ) : subscriptions.isError ? (
        <Alert>{adminMessage(subscriptions.error.message, t)}</Alert>
      ) : !subscriptions.data.length ? (
        <p>{t("WebAdminNoPodcastSubscriptionsYetAddAPodcast")}</p>
      ) : (
        subscriptions.data.map((subscription) => (
          <Subscription key={subscription.id} subscription={subscription} />
        ))
      )}
    </section>
  );
}
function Subscription({ subscription }: { subscription: z.infer<typeof subscriptionSchema> }) {
  const feedbackId = useId();
  const { t } = useI18n();
  const { client, connection } = useAbs();
  const queries = useQueryClient();
  const [result, action, pending] = useActionState<Result, FormData>(
    async (_previous, form) => {
      try {
        await client.command("PATCH", `/api/podcasts/${encodeURIComponent(subscription.id)}/schedule`, {
          autoDownloadEpisodes: form.get("autoDownloadEpisodes") === "on",
        });
        if (form.get("mode") === "check")
          await client.command("POST", `/api/podcasts/${encodeURIComponent(subscription.id)}/check`, {});
        await queries.invalidateQueries({ queryKey: [connection.id, "podcast-subscriptions"] });
        await queries.invalidateQueries({ queryKey: [connection.id, "library"] });
        return { kind: "saved" };
      } catch (error) {
        await queries.invalidateQueries({ queryKey: [connection.id, "podcast-subscriptions"] });
        return {
          kind: "error",
          message: error instanceof Error ? error.message : "Subscription update failed",
        };
      }
    },
    { kind: "idle" },
  );
  return (
    <form
      aria-describedby={result.kind === "error" ? feedbackId : undefined}
      action={action}
      className="flex flex-col gap-3 rounded-xl bg-surface p-5"
    >
      <h3 className="font-semibold">{subscription.title}</h3>
      <p className="text-sm text-muted">
        {subscription.leaseUntil
          ? t("WebAdminCheckingFeed")
          : subscription.lastCheckedAt
            ? `Last checked ${new Date(subscription.lastCheckedAt).toLocaleString()}`
            : t("WebAdminNotCheckedYet")}
      </p>
      <Toggle
        name="autoDownloadEpisodes"
        label={t("WebAdminAutomaticallyDownloadNewEpisodes")}
        defaultChecked={subscription.autoDownloadEpisodes}
      />
      {subscription.lastError ? <Alert>{subscription.lastError}</Alert> : null}
      {result.kind === "error" ? (
        <FormFeedback submission={result} id={feedbackId}>
          {adminMessage(result.message, t)}
        </FormFeedback>
      ) : result.kind === "saved" ? (
        <p role="status">{t("WebAdminSubscriptionSaved")}</p>
      ) : null}
      <div className="flex flex-wrap gap-2">
        <Button type="submit" name="mode" value="save" disabled={pending}>
          {t("WebAdminSaveSubscription")}
        </Button>
        <Button type="submit" name="mode" value="check" disabled={pending}>
          {t("WebAdminCheckNow")}
        </Button>
        <ButtonLink href={`/item/${encodeURIComponent(subscription.id)}`}>
          {t("WebAdminOpenPodcast")}
        </ButtonLink>
      </div>
    </form>
  );
}
