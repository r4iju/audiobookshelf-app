"use client";

import { Send } from "lucide-react";
import { useState } from "react";
import { errorMessage } from "@/components/app/errors";
import { Button } from "@/components/ui/button";
import { Dialog } from "@/components/ui/dialog";
import { useI18n } from "@/i18n/i18n";
import { useSendEbook } from "@/lib/abs/mutations";
import { useEreaderDevices } from "@/lib/abs/queries";

export interface SendResult {
  tone: "info" | "danger";
  text: string;
}

/** Shown only when the server lists e-readers this account may use. */
export function SendEbookButton({
  itemId,
  onResult,
}: {
  itemId: string;
  onResult: (result: SendResult) => void;
}) {
  const { t } = useI18n();
  const devices = useEreaderDevices().data ?? [];
  const send = useSendEbook();
  const [choosing, setChoosing] = useState(false);
  if (!devices.length) return null;
  return (
    <>
      <Button onClick={() => setChoosing(true)} disabled={send.isPending}>
        <Send aria-hidden className="size-4" />
        {t("ButtonSendEbookToDevice")}
      </Button>
      <Dialog open={choosing} onClose={() => setChoosing(false)} title={t("LabelSelectADevice")}>
        <ul className="flex flex-col gap-1">
          {devices.map((device) => (
            <li key={device.name}>
              <Button
                variant="ghost"
                className="w-full justify-start"
                onClick={() => {
                  setChoosing(false);
                  send.mutate(
                    { itemId, deviceName: device.name },
                    {
                      onSuccess: () => onResult({ tone: "info", text: t("WebEbookSent", device.name) }),
                      onError: (error) =>
                        onResult({ tone: "danger", text: t("WebEbookSendFailed", errorMessage(t, error)) }),
                    },
                  );
                }}
              >
                {device.name}
              </Button>
            </li>
          ))}
        </ul>
        <div className="flex justify-end">
          <Button variant="ghost" onClick={() => setChoosing(false)}>
            {t("WebCancel")}
          </Button>
        </div>
      </Dialog>
    </>
  );
}
