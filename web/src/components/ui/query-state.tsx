"use client";

import type { UseQueryResult } from "@tanstack/react-query";
import type { ReactNode } from "react";
import { errorMessage } from "@/components/app/errors";
import { useI18n } from "@/i18n/i18n";
import { Button } from "./button";
import { Alert, Spinner } from "./status";

/** Explicit loading and error branches for one query; children render only with data. */
export function QueryState<T>({
  query,
  children,
}: {
  query: UseQueryResult<T>;
  children: (data: T) => ReactNode;
}) {
  const { t } = useI18n();
  if (query.isPending) return <Spinner label={t("MessageLoading")} />;
  if (query.isError) {
    return (
      <Alert
        action={
          <Button size="sm" onClick={() => query.refetch()}>
            {t("WebRetry")}
          </Button>
        }
      >
        {errorMessage(t, query.error)}
      </Alert>
    );
  }
  return children(query.data);
}
