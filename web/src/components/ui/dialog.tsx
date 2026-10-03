"use client";

import { type ReactNode, useEffect, useId, useState } from "react";
import { PopupLayer } from "./popup";

/** A modal built on the native dialog element: focus trapping, Escape and the top layer come from the browser. */
export function Dialog({
  open,
  onClose,
  title,
  children,
}: {
  open: boolean;
  onClose: () => void;
  title: string;
  children: ReactNode;
}) {
  const [dialog, setDialog] = useState<HTMLDialogElement | null>(null);
  const titleId = useId();

  // External system: the dialog element's modal state.
  useEffect(() => {
    if (!dialog) return;
    if (!open) {
      if (dialog.open) dialog.close();
      return;
    }
    if (dialog.open) return;
    const opener = document.activeElement instanceof HTMLElement ? document.activeElement : null;
    dialog.showModal();
    // Conditionally mounted dialogs can disappear before native close restores the opener.
    return () => {
      if (dialog.open) dialog.close();
      if (opener?.isConnected) opener.focus({ preventScroll: true });
    };
  }, [open, dialog]);

  return (
    <dialog
      ref={setDialog}
      onClose={onClose}
      aria-labelledby={titleId}
      className="m-auto w-[min(28rem,calc(100vw-2rem))] rounded-[var(--radius-card)] bg-surface p-0 text-fg shadow-2xl backdrop:bg-black/60"
    >
      {open ? (
        <PopupLayer value={dialog}>
          <div className="flex flex-col gap-4 p-5">
            <h2 id={titleId} className="text-lg font-semibold">
              {title}
            </h2>
            {children}
          </div>
        </PopupLayer>
      ) : null}
    </dialog>
  );
}

export function ConfirmDialog({
  open,
  title,
  body,
  confirmLabel,
  cancelLabel,
  onConfirm,
  onClose,
  busy,
}: {
  open: boolean;
  title: string;
  body?: string;
  confirmLabel: string;
  cancelLabel: string;
  onConfirm: () => void;
  onClose: () => void;
  busy?: boolean;
}) {
  return (
    <Dialog open={open} onClose={onClose} title={title}>
      {body ? <p className="text-sm text-muted">{body}</p> : null}
      <div className="flex justify-end gap-2">
        <button
          type="button"
          onClick={onClose}
          className="min-h-11 rounded-xl px-4 text-sm font-semibold hover:bg-surface-2 focus-ring"
        >
          {cancelLabel}
        </button>
        <button
          type="button"
          disabled={busy}
          onClick={onConfirm}
          className="min-h-11 rounded-xl bg-danger-strong px-4 text-sm font-semibold text-white disabled:opacity-50 focus-ring"
        >
          {confirmLabel}
        </button>
      </div>
    </Dialog>
  );
}
