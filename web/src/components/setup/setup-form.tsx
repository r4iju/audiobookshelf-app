"use client";
import { useActionState, useId } from "react";
import { initialize, type SetupResult } from "@/app/setup/actions";
import { Button, ButtonLink } from "@/components/ui/button";
import { TextField } from "@/components/ui/field";
import { FormFeedback } from "@/components/ui/form-feedback";
import { useI18n } from "@/i18n/i18n";
import { adminMessage } from "@/lib/abs/administration-messages";

const initial: SetupResult = { status: "idle" };
export function SetupForm() {
  const feedbackId = useId();
  const { t } = useI18n();
  const [result, action, pending] = useActionState(initialize, initial);
  if (result.status === "complete")
    return (
      <div className="space-y-4">
        <p>{t("WebAdminYourServerIsReadySignInWith")}</p>
        <ButtonLink href="/connect" variant="primary">
          {t("WebSignIn")}
        </ButtonLink>
      </div>
    );
  return (
    <form
      aria-describedby={result.status === "error" ? feedbackId : undefined}
      action={action}
      className="space-y-5"
    >
      <TextField
        label={t("LabelUsername")}
        name="username"
        autoComplete="username"
        required
        minLength={3}
        maxLength={64}
      />
      <TextField
        label={t("LabelPassword")}
        name="password"
        type="password"
        autoComplete="new-password"
        required
        minLength={12}
        maxLength={512}
        help={t("WebAdminUseAtLeast12Characters618b57")}
      />
      <TextField
        label={t("WebAdminSetupKey")}
        name="setupKey"
        type="password"
        autoComplete="off"
        required
        help={t("WebAdminReadSetupKeyFromYourMountedLeafwake")}
      />
      {result.status === "error" ? (
        <FormFeedback submission={result} id={feedbackId}>
          {adminMessage(result.message, t)}
        </FormFeedback>
      ) : null}
      <Button type="submit" variant="primary" disabled={pending}>
        {pending ? t("WebAdminCreatingAccount") : t("WebAdminCreateOwnerAccount")}
      </Button>
    </form>
  );
}
