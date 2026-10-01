"use client";

import { type ReactNode, useEffect, useRef } from "react";

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
  const ref = useRef<HTMLDialogElement>(null);

  // External system: the dialog element's modal state.
  useEffect(() => {
    const dialog = ref.current;
    if (!dialog) return;
    if (open && !dialog.open) dialog.showModal();
    if (!open && dialog.open) dialog.close();
  }, [open]);

  return (
    <dialog
      ref={ref}
      onClose={onClose}
      aria-labelledby="dialog-title"
      className="m-auto w-[min(28rem,calc(100vw-2rem))] rounded-[var(--radius-card)] bg-surface p-0 text-fg shadow-2xl backdrop:bg-black/60"
    >
      {open ? (
        <div className="flex flex-col gap-4 p-5">
          <h2 id="dialog-title" className="text-lg font-semibold">
            {title}
          </h2>
          {children}
        </div>
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
          className="min-h-11 rounded-xl bg-danger px-4 text-sm font-semibold text-white disabled:opacity-50 focus-ring"
        >
          {confirmLabel}
        </button>
      </div>
    </Dialog>
  );
}
