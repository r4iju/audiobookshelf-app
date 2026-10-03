import { Check } from "lucide-react";
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
        className="min-h-11 rounded-xl border border-muted bg-surface px-3 text-base text-fg placeholder:text-muted focus-ring"
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

type SwitchSize = "md" | "sm";

const tracks: Record<SwitchSize, string> = { md: "h-6 w-10", sm: "h-5 w-8" };
const thumbs: Record<SwitchSize, string> = {
  md: "size-4 peer-checked:translate-x-4 rtl:peer-checked:-translate-x-4",
  sm: "size-3 peer-checked:translate-x-3 rtl:peer-checked:-translate-x-3",
};

/** The browser's own input keeps the label, Space, form and disabled behaviour; only its drawing is the app's. */
function Switch({ size, ...props }: Omit<ComponentProps<"input">, "type" | "size"> & { size: SwitchSize }) {
  return (
    <span className="relative inline-flex shrink-0">
      <input
        type="checkbox"
        role="switch"
        aria-checked={props.checked}
        className={`peer cursor-pointer appearance-none rounded-full border border-muted bg-surface-3 transition-colors checked:border-muted checked:bg-accent-strong disabled:cursor-not-allowed disabled:opacity-50 focus-ring ${tracks[size]}`}
        {...props}
      />
      <span
        aria-hidden
        className={`pointer-events-none absolute start-1 top-1 rounded-full bg-muted shadow-sm transition-transform peer-checked:bg-white peer-disabled:opacity-50 ${thumbs[size]}`}
      />
    </span>
  );
}

export function Toggle({
  label,
  help,
  ...props
}: Omit<ComponentProps<"input">, "type" | "size"> & { label: string; help?: string }) {
  const id = useId();
  return (
    <div className="flex items-start justify-between gap-4 py-2">
      <label htmlFor={id} className="flex cursor-pointer flex-col">
        <span className="text-sm font-medium">{label}</span>
        {help ? <span className="text-xs text-muted">{help}</span> : null}
      </label>
      <Switch id={id} size="md" {...props} />
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
    <label className="flex min-h-9 cursor-pointer items-center gap-2 text-xs font-medium">
      <Switch size="sm" checked={checked} onChange={(event) => onChange(event.target.checked)} />
      {label}
    </label>
  );
}

/** A choice among many, such as episodes to download, drawn in the app's colours rather than the browser's. */
export function Checkbox({ className = "", ...props }: Omit<ComponentProps<"input">, "type">) {
  return (
    <span className={`relative inline-flex size-5 shrink-0 ${className}`}>
      <input
        type="checkbox"
        className="peer size-5 cursor-pointer appearance-none rounded-md border-2 border-muted bg-surface transition-colors checked:border-muted checked:bg-accent-strong disabled:cursor-not-allowed disabled:opacity-40 focus-ring"
        {...props}
      />
      <Check
        aria-hidden
        strokeWidth={3}
        className="pointer-events-none absolute inset-0.5 size-4 text-accent-fg opacity-0 peer-checked:opacity-100"
      />
    </span>
  );
}
