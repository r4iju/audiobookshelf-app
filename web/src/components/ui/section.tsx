import { type ReactNode, useId } from "react";

/** A titled card that assistive technology lists as a region under its title. */
export function Section({ title, children }: { title: string; children: ReactNode }) {
  const id = useId();
  return (
    <section aria-labelledby={id} className="flex flex-col gap-3 rounded-[var(--radius-card)] bg-surface p-5">
      <h2 id={id} className="text-sm font-semibold tracking-wide text-muted uppercase">
        {title}
      </h2>
      {children}
    </section>
  );
}
