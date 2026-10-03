"use client";

import * as Select from "@radix-ui/react-select";
import { Check, ChevronDown } from "lucide-react";
import { useId } from "react";
import { popupItem, popupPanel, useDirection, usePopupLayer } from "./popup";

export type SelectOption = { value: string; label: string; lang?: string };
export type SelectGroup = { label: string; options: readonly SelectOption[] };
type Size = "md" | "sm";

// Radix reserves the empty string for "nothing chosen", where these fields use it as a real choice such as "All".
const EMPTY = "__empty";
const toList = (value: string) => (value === "" ? EMPTY : value);
const fromList = (value: string) => (value === EMPTY ? "" : value);

const triggers: Record<Size, string> = {
  md: "min-h-11 rounded-xl px-3 text-base",
  sm: "min-h-9 rounded-lg px-2.5 text-sm",
};
const labels: Record<Size, string> = { md: "text-sm font-medium", sm: "text-xs font-medium" };

/** A labelled choice whose list is the app's own popup; inside a form it still submits and validates as a select. */
export function SelectField({
  label,
  options,
  value,
  defaultValue,
  onChange,
  name,
  required,
  disabled,
  size = "md",
  className = "",
}: {
  label: string;
  options: ReadonlyArray<SelectOption | SelectGroup>;
  value?: string;
  defaultValue?: string;
  onChange?: (value: string) => void;
  name?: string;
  required?: boolean;
  disabled?: boolean;
  size?: Size;
  className?: string;
}) {
  const id = useId();
  const layer = usePopupLayer();
  const dir = useDirection();
  return (
    <div className={`flex flex-col gap-1.5 ${className}`}>
      <label htmlFor={id} className={labels[size]}>
        {label}
      </label>
      <Select.Root
        dir={dir}
        name={name}
        required={required}
        disabled={disabled}
        value={value === undefined ? undefined : toList(value)}
        defaultValue={defaultValue === undefined ? undefined : toList(defaultValue)}
        onValueChange={(next) => onChange?.(fromList(next))}
      >
        <Select.Trigger
          id={id}
          className={`flex items-center justify-between gap-2 border border-muted bg-surface text-start text-fg hover:border-muted focus-ring disabled:cursor-not-allowed disabled:opacity-50 data-[state=open]:border-accent ${triggers[size]}`}
        >
          <span className="min-w-0 truncate">
            <Select.Value />
          </span>
          <Select.Icon>
            <ChevronDown aria-hidden className="size-4 shrink-0 text-muted" />
          </Select.Icon>
        </Select.Trigger>
        <Select.Portal container={layer}>
          <Select.Content
            position="popper"
            sideOffset={6}
            collisionPadding={8}
            className={`${popupPanel} max-h-[min(22rem,var(--radix-select-content-available-height))] min-w-[var(--radix-select-trigger-width)]`}
          >
            <Select.Viewport>
              {options.map((entry) =>
                "options" in entry ? (
                  <Select.Group key={entry.label}>
                    <Select.Label className="px-3 pt-2 pb-1 text-xs font-semibold text-muted uppercase">
                      {entry.label}
                    </Select.Label>
                    {entry.options.map((option) => (
                      <Item key={option.value} option={option} />
                    ))}
                  </Select.Group>
                ) : (
                  <Item key={entry.value} option={entry} />
                ),
              )}
            </Select.Viewport>
          </Select.Content>
        </Select.Portal>
      </Select.Root>
    </div>
  );
}

function Item({ option }: { option: SelectOption }) {
  return (
    <Select.Item value={toList(option.value)} lang={option.lang} className={popupItem}>
      <Select.ItemIndicator className="absolute start-2.5 inline-flex text-accent">
        <Check aria-hidden className="size-4" />
      </Select.ItemIndicator>
      <Select.ItemText>{option.label}</Select.ItemText>
    </Select.Item>
  );
}
