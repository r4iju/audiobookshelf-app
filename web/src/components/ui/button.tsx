import Link from "next/link";
import type { ComponentProps } from "react";

type Variant = "primary" | "secondary" | "ghost" | "danger";
type Size = "md" | "sm" | "icon";

const variants: Record<Variant, string> = {
  primary: "bg-accent-strong text-accent-fg hover:bg-accent disabled:opacity-50",
  secondary: "bg-surface-2 text-fg hover:bg-surface-3 disabled:opacity-50",
  ghost: "text-fg hover:bg-surface-2 disabled:opacity-40",
  danger: "bg-surface-2 text-danger hover:bg-surface-3 disabled:opacity-50",
};
const sizes: Record<Size, string> = {
  md: "min-h-11 px-4 rounded-xl text-sm font-semibold gap-2",
  sm: "min-h-9 px-3 rounded-lg text-sm font-medium gap-1.5",
  icon: "size-11 rounded-full justify-center",
};

export function buttonClass(variant: Variant = "secondary", size: Size = "md") {
  return `inline-flex items-center justify-center transition-colors focus-ring disabled:cursor-not-allowed ${variants[variant]} ${sizes[size]}`;
}

export function Button({
  variant,
  size,
  className = "",
  type = "button",
  ...props
}: ComponentProps<"button"> & { variant?: Variant; size?: Size }) {
  return <button type={type} className={`${buttonClass(variant, size)} ${className}`} {...props} />;
}

export function ButtonLink({
  variant,
  size,
  className = "",
  ...props
}: ComponentProps<typeof Link> & { variant?: Variant; size?: Size }) {
  return <Link className={`${buttonClass(variant, size)} ${className}`} {...props} />;
}
