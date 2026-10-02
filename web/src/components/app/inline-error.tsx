"use client";

import { useI18n } from "@/i18n/i18n";
import { errorMessage } from "./errors";

export function InlineError({ error }: { error: Error | null }) {
  const { t } = useI18n();
  if (!error) return null;
  return (
    <p role="alert" className="text-sm text-danger">
      {errorMessage(t, error)}
    </p>
  );
}
