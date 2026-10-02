import { type ComponentProps, useId } from "react";

export function TextField({
  label,
  help,
  className = "",
  ...props
}: ComponentProps<"input"> & { label: string; help?: string }) {
  const id = useId();
  return (
    <div className={`flex flex-col gap-1.5 ${className}`}>
      <label htmlFor={id} className="text-sm font-medium">
        {label}
      </label>
      <input
        id={id}
        aria-describedby={help ? `${id}-help` : undefined}
        className="min-h-11 rounded-xl border border-line bg-surface px-3 text-base text-fg placeholder:text-muted focus-ring"
        {...props}
      />
      {help ? (
        <p id={`${id}-help`} className="text-xs text-muted">
          {help}
        </p>
      ) : null}
    </div>
  );
}

export function Toggle({
  label,
  help,
  ...props
}: Omit<ComponentProps<"input">, "type"> & { label: string; help?: string }) {
  const id = useId();
  return (
    <div className="flex items-start justify-between gap-4 py-2">
      <label htmlFor={id} className="flex flex-col">
        <span className="text-sm font-medium">{label}</span>
        {help ? <span className="text-xs text-muted">{help}</span> : null}
      </label>
      <input
        id={id}
        type="checkbox"
        role="switch"
        aria-checked={props.checked}
        className="mt-1 size-5 shrink-0 accent-[var(--accent-strong)] focus-ring"
        {...props}
      />
    </div>
  );
}

/** A switch with its label beside it, for toolbars and control rows. */
export function InlineToggle({
  label,
  checked,
  onChange,
}: {
  label: string;
  checked: boolean;
  onChange: (checked: boolean) => void;
}) {
  return (
    <label className="flex min-h-9 items-center gap-2 text-xs font-medium">
      <input
        type="checkbox"
        role="switch"
        aria-checked={checked}
        checked={checked}
        onChange={(event) => onChange(event.target.checked)}
        className="size-4 accent-[var(--accent-strong)] focus-ring"
      />
      {label}
    </label>
  );
}
