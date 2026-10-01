import type { Translate } from "@/i18n/i18n";
import { AbsError } from "@/lib/abs/client";

export function errorMessage(t: Translate, error: unknown) {
  if (!(error instanceof AbsError)) return t("WebErrorGeneric");
  switch (error.kind) {
    case "network":
      return t("WebOffline");
    case "unauthorized":
      return t("WebSignInToContinue");
    case "forbidden":
      return t("WebForbidden");
    case "not-found":
      return t("WebNotFound");
    case "http":
      return t("WebErrorServer", error.status ?? "?");
    case "invalid-response":
      return error.message;
  }
}
