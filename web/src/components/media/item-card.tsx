import { CheckCircle2 } from "lucide-react";
import Link from "next/link";
import type { ReactNode } from "react";
import type { CoverShape } from "@/lib/abs/media";
import { Cover, ProgressBar } from "./cover";

export type CardLayout = "grid" | "list";

export interface CardProgress {
  value: number;
  finished: boolean;
}

/**
 * Fixed-height text block under a fixed-shape cover keeps every card in a row the same height. As a list row, the
 * cover sits beside the text, which adds `detail` (such as the length), as in the legacy bookshelf's list view.
 */
export function MediaCard({
  href,
  title,
  subtitle,
  detail,
  cover,
  shape,
  badge,
  progress,
  progressLabel,
  finishedLabel,
  missingCoverLabel,
  layout = "grid",
}: {
  href: string;
  title: string;
  subtitle?: string;
  detail?: string;
  cover: string | null;
  shape: CoverShape;
  badge?: string;
  progress?: CardProgress;
  progressLabel: string;
  finishedLabel: string;
  missingCoverLabel: string;
  layout?: CardLayout;
}) {
  const partly = progress && !progress.finished && progress.value > 0 ? progress.value : null;
  if (layout === "list") {
    return (
      <Link
        href={href}
        className="group flex w-full items-center gap-3 rounded-xl p-2 hover:bg-surface-2 focus-ring"
      >
        <div className="relative w-14 shrink-0">
          <Cover missingLabel={missingCoverLabel} src={cover} title={title} shape={shape} compact />
          {partly !== null ? (
            <div aria-hidden className="absolute inset-x-0 bottom-0">
              <ProgressBar value={partly} label={progressLabel} />
            </div>
          ) : null}
        </div>
        <div className="min-w-0 flex-1">
          <p className="truncate text-sm font-semibold">{title}</p>
          {subtitle ? <p className="truncate text-xs text-muted">{subtitle}</p> : null}
          {detail ? <p className="text-xs text-muted tabular-nums">{detail}</p> : null}
          {partly !== null ? (
            <span className="sr-only">{`${progressLabel} ${Math.round(partly * 100)}%`}</span>
          ) : null}
        </div>
        {badge ? (
          <span className="rounded-full bg-surface-2 px-2 py-0.5 text-xs font-semibold">{badge}</span>
        ) : null}
        {progress?.finished ? (
          <CheckCircle2 aria-label={finishedLabel} className="size-4 shrink-0 text-success" />
        ) : null}
      </Link>
    );
  }
  return (
    <Link href={href} className="group flex w-full flex-col gap-2 rounded-xl focus-ring">
      <div className="relative">
        <Cover
          missingLabel={missingCoverLabel}
          src={cover}
          title={title}
          subtitle={subtitle}
          shape={shape}
          className="transition-transform group-hover:-translate-y-0.5"
        />
        {badge ? (
          <span className="absolute top-2 right-2 rounded-full bg-overlay px-2 py-0.5 text-xs font-semibold text-white">
            {badge}
          </span>
        ) : null}
        {progress?.finished ? (
          <span className="absolute right-2 bottom-2 rounded-full bg-overlay p-1 text-success">
            <CheckCircle2 aria-label={finishedLabel} className="size-4" />
          </span>
        ) : null}
      </div>
      {/* A progressbar inside a link would leave the link without a name, so the bar is drawn and the value is told. */}
      <div aria-hidden className="h-1">
        {progress && !progress.finished && progress.value > 0 ? (
          <ProgressBar value={progress.value} label={progressLabel} />
        ) : null}
      </div>
      <div className="h-14 overflow-hidden">
        <p className="line-clamp-2 text-sm font-semibold leading-snug break-words">{title}</p>
        {subtitle ? <p className="truncate text-xs text-muted">{subtitle}</p> : null}
        {progress && !progress.finished && progress.value > 0 ? (
          <span className="sr-only">{`${progressLabel} ${Math.round(progress.value * 100)}%`}</span>
        ) : null}
      </div>
    </Link>
  );
}

export const shelfWidths: Record<CoverShape, string> = { book: "w-32 sm:w-36", square: "w-36 sm:w-44" };

export function CardGrid({
  shape,
  children,
  label,
  layout = "grid",
}: {
  shape: CoverShape;
  children: ReactNode;
  label?: string;
  layout?: CardLayout;
}) {
  if (layout === "list") {
    return (
      <ul aria-label={label} className="flex flex-col gap-1">
        {children}
      </ul>
    );
  }
  return (
    <ul
      aria-label={label}
      className={`grid gap-x-4 gap-y-6 ${shape === "book" ? "grid-cols-[repeat(auto-fill,minmax(8rem,1fr))] sm:grid-cols-[repeat(auto-fill,minmax(9.5rem,1fr))]" : "grid-cols-[repeat(auto-fill,minmax(9rem,1fr))] sm:grid-cols-[repeat(auto-fill,minmax(11rem,1fr))]"}`}
    >
      {children}
    </ul>
  );
}
