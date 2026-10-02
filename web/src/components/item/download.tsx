"use client";

import { useMutation } from "@tanstack/react-query";
import { Download } from "lucide-react";
import { InlineError } from "@/components/app/inline-error";
import { Button } from "@/components/ui/button";
import { useI18n } from "@/i18n/i18n";
import { useAbs } from "@/lib/session/store";

/**
 * Saves the item's files as the server packs them. The browser downloads them itself so large books never pass
 * through memory, which means the server's `token` query parameter carries the sign-in, as in the server's own web
 * interface; renewing the sign-in first keeps an expired one from turning the download into an error page.
 */
export function DownloadButton({ itemId }: { itemId: string }) {
  const { t } = useI18n();
  const { client } = useAbs();
  const download = useMutation({
    mutationFn: async () => {
      await client.command("POST", "/api/authorize");
      const link = document.createElement("a");
      link.href = client.url(`/api/items/${itemId}/download?token=${encodeURIComponent(client.bearer)}`);
      link.rel = "noreferrer";
      link.click();
    },
  });
  return (
    <>
      <Button onClick={() => download.mutate()} disabled={download.isPending}>
        <Download aria-hidden className="size-4" />
        {t("LabelDownload")}
      </Button>
      <InlineError error={download.error} />
    </>
  );
}
