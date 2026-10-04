"use client";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import { useActionState, useId } from "react";
import { z } from "zod";
import { Button, ButtonLink } from "@/components/ui/button";
import { TextField, Toggle } from "@/components/ui/field";
import { FormFeedback } from "@/components/ui/form-feedback";
import { Section } from "@/components/ui/section";
import { SelectField } from "@/components/ui/select";
import { Alert, EmptyState, Spinner } from "@/components/ui/status";
import { useI18n } from "@/i18n/i18n";
import { adminMessage } from "@/lib/abs/administration-messages";
import { providerSettingsInput } from "@/lib/abs/item-management";
import { librariesResponseSchema, libraryItemSchema } from "@/lib/abs/schemas";
import { useAbs } from "@/lib/session/store";

type Result = { kind: "idle" } | { kind: "error"; message: string } | { kind: "uploaded"; itemId: string };
export function UploadScreen() {
  const feedbackId = useId();
  const { t } = useI18n();
  const { client, connection } = useAbs(),
    queries = useQueryClient();
  const libraries = useQuery({
    queryKey: [connection.id, "libraries"],
    queryFn: ({ signal }) => client.get("/api/libraries", librariesResponseSchema, signal),
  });
  const [result, submit, pending] = useActionState<Result, FormData>(
    async (_prior, form) => {
      try {
        const id = z.string().min(1).parse(form.get("libraryId")),
          file = z.instanceof(File).parse(form.get("file"));
        if (!file.size || file.size > 1024 * 1024 * 1024)
          throw new Error("Choose a nonempty media file up to 1 GiB");
        const uploaded = await client.upload(
          `/api/libraries/${encodeURIComponent(id)}/upload?filename=${encodeURIComponent(file.name)}`,
          file,
          z.object({ item: libraryItemSchema }),
        );
        await queries.invalidateQueries({ queryKey: [connection.id] });
        return { kind: "uploaded", itemId: uploaded.item.id };
      } catch (error) {
        return { kind: "error", message: error instanceof Error ? error.message : "Upload failed" };
      }
    },
    { kind: "idle" },
  );
  const books = libraries.data?.libraries.filter((l) => l.mediaType === "book") ?? [];
  return (
    <div className="mx-auto flex max-w-3xl flex-col gap-6">
      <h1 className="text-2xl font-bold">{t("WebAdminUploadAndMetadata")}</h1>
      <Section title={t("WebAdminUploadABook")}>
        <p className="text-sm text-muted">{t("WebAdminChooseABookLibraryContainingTheManaged")}</p>
        {libraries.isPending ? (
          <Spinner label={t("WebAdminLoadingLibraries")} />
        ) : libraries.isError ? (
          <Alert>{adminMessage(libraries.error.message, t)}</Alert>
        ) : books.length ? (
          <form
            aria-describedby={result.kind === "error" ? feedbackId : undefined}
            action={submit}
            className="space-y-4"
          >
            <SelectField
              name="libraryId"
              label={t("WebAdminBookLibrary")}
              options={books.map((l) => ({ value: l.id, label: l.name }))}
            />
            <TextField
              name="file"
              type="file"
              label={t("WebAdminAudioOrEbookFile")}
              accept=".mp3,.m4b,.m4a,.flac,.ogg,.opus,.wav,.aac,.epub,.pdf,.mobi,.azw3,.cbz,.cbr"
              required
            />
            {result.kind === "error" ? (
              <FormFeedback submission={result} id={feedbackId}>
                {adminMessage(result.message, t)}
              </FormFeedback>
            ) : result.kind === "uploaded" ? (
              <p role="status">
                {t("WebAdminUploadComplete")}{" "}
                <ButtonLink href={`/admin/items/${encodeURIComponent(result.itemId)}`}>
                  {t("WebAdminEditUploadedItem")}
                </ButtonLink>
              </p>
            ) : null}
            <Button type="submit" disabled={pending}>
              {pending ? t("WebAdminUploading") : t("WebAdminUploadBook")}
            </Button>
          </form>
        ) : (
          <EmptyState title={t("WebAdminCreateABookLibraryFirst")} />
        )}
      </Section>
      <ProviderConfiguration />
    </div>
  );
}
function ProviderConfiguration() {
  const { t } = useI18n();
  const { client, connection } = useAbs();
  const provider = useQuery({
    queryKey: [connection.id, "metadata-provider"],
    queryFn: ({ signal }) => client.get("/api/admin/metadata-provider", providerSettingsInput, signal),
  });
  return (
    <Section title={t("WebAdminOptionalMetadataProvider")}>
      {provider.isPending ? (
        <Spinner label={t("WebAdminLoadingProviderSettings")} />
      ) : provider.isError ? (
        <Alert>{adminMessage(provider.error.message, t)}</Alert>
      ) : (
        <ProviderForm key={JSON.stringify(provider.data)} initial={provider.data} />
      )}
    </Section>
  );
}
function ProviderForm({ initial }: { initial: z.infer<typeof providerSettingsInput> }) {
  const feedbackId = useId();
  const { t } = useI18n();
  const { client, connection } = useAbs(),
    queries = useQueryClient();
  type State = { kind: "idle" } | { kind: "error"; message: string } | { kind: "saved" };
  const [result, submit, pending] = useActionState<State, FormData>(
    async (_prior, form) => {
      try {
        await client.send(
          "PATCH",
          "/api/admin/metadata-provider",
          providerSettingsInput.parse({
            enabled: form.get("enabled") === "on",
            searchUrl: form.get("searchUrl"),
          }),
          providerSettingsInput,
        );
        await queries.invalidateQueries({ queryKey: [connection.id, "metadata-provider"] });
        return { kind: "saved" };
      } catch (error) {
        return {
          kind: "error",
          message: error instanceof Error ? error.message : "Provider settings failed",
        };
      }
    },
    { kind: "idle" },
  );
  return (
    <form
      aria-describedby={result.kind === "error" ? feedbackId : undefined}
      action={submit}
      className="space-y-4"
    >
      <p className="text-sm text-muted">{t("WebAdminDisabledByDefaultEnablingThisProviderSends")}</p>
      <Toggle name="enabled" label={t("WebAdminEnableMetadataSearch")} defaultChecked={initial.enabled} />
      <TextField
        name="searchUrl"
        label={t("WebAdminHTTPSSearchEndpoint")}
        type="url"
        required
        defaultValue={initial.searchUrl}
      />
      {result.kind === "error" ? (
        <FormFeedback submission={result} id={feedbackId}>
          {adminMessage(result.message, t)}
        </FormFeedback>
      ) : result.kind === "saved" ? (
        <p role="status">{t("WebAdminProviderSettingsSaved")}</p>
      ) : null}
      <Button type="submit" disabled={pending}>
        {t("WebAdminSaveProviderSettings")}
      </Button>
    </form>
  );
}
