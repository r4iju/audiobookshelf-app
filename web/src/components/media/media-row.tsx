import Link from "next/link";
import type { ReactNode } from "react";
import { Cover } from "./cover";

/** A list row with a fixed square thumbnail, so rows line up whatever the artwork's proportions. */
export function MediaRow({
  href,
  cover,
  title,
  subtitle,
  meta,
  missingCoverLabel,
  actions,
}: {
  href: string;
  cover: string | null;
  title: string;
  subtitle?: string;
  meta?: ReactNode;
  missingCoverLabel: string;
  actions?: ReactNode;
}) {
  return (
    <li className="flex items-center gap-3 px-3 py-3 sm:gap-4 sm:px-4">
      <Link href={href} tabIndex={-1} aria-hidden className="w-14 shrink-0 sm:w-16">
        <Cover src={cover} title={title} shape="square" missingLabel={missingCoverLabel} compact />
      </Link>
      <div className="flex min-w-0 flex-1 flex-col gap-0.5">
        <h3 className="font-medium break-words">
          <Link href={href} className="rounded hover:underline focus-ring">
            {title}
          </Link>
        </h3>
        {subtitle ? <p className="truncate text-sm text-muted">{subtitle}</p> : null}
        {meta ? <div className="text-xs text-muted">{meta}</div> : null}
      </div>
      {actions ? <div className="flex shrink-0 items-center gap-1">{actions}</div> : null}
    </li>
  );
}
