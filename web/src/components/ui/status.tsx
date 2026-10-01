import { AlertTriangle, Loader2 } from "lucide-react";
import type { ReactNode } from "react";

export function Alert({
  children,
  tone = "danger",
  action,
}: {
  children: ReactNode;
  tone?: "danger" | "info";
  action?: ReactNode;
}) {
  return (
    <div
      role={tone === "danger" ? "alert" : "status"}
      className={`flex items-start gap-3 rounded-xl border px-4 py-3 text-sm ${tone === "danger" ? "border-danger/40 bg-danger/10" : "border-line bg-surface-2"}`}
    >
      {tone === "danger" ? (
        <AlertTriangle aria-hidden className="mt-0.5 size-4 shrink-0 text-danger" />
      ) : null}
      <div className="flex-1">{children}</div>
      {action}
    </div>
  );
}

export function Spinner({ label }: { label: string }) {
  return (
    <div role="status" className="flex items-center justify-center gap-2 py-10 text-muted">
      <Loader2 aria-hidden className="size-5 animate-spin" />
      <span>{label}</span>
    </div>
  );
}

export function EmptyState({ title, children }: { title: string; children?: ReactNode }) {
  return (
    <div className="flex flex-col items-center gap-2 rounded-[var(--radius-card)] border border-dashed border-line px-6 py-12 text-center">
      <p className="font-semibold">{title}</p>
      {children ? <div className="text-sm text-muted">{children}</div> : null}
    </div>
  );
}
