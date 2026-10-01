import { CheckCircle2 } from "lucide-react";
import Link from "next/link";
import type { ReactNode } from "react";
import type { CoverShape } from "@/lib/abs/media";
import { Cover, ProgressBar } from "./cover";

export interface CardProgress {
  value: number;
  finished: boolean;
}

/** Fixed-height text block under a fixed-shape cover keeps every card in a row the same height. */
export function MediaCard({
  href,
  title,
  subtitle,
  cover,
  shape,
  badge,
  progress,
  progressLabel,
  finishedLabel,
  missingCoverLabel,
}: {
  href: string;
  title: string;
  subtitle?: string;
  cover: string | null;
  shape: CoverShape;
  badge?: string;
  progress?: CardProgress;
  progressLabel: string;
  finishedLabel: string;
  missingCoverLabel: string;
}) {
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
}: {
  shape: CoverShape;
  children: ReactNode;
  label?: string;
}) {
  return (
    <ul
      aria-label={label}
      className={`grid gap-x-4 gap-y-6 ${shape === "book" ? "grid-cols-[repeat(auto-fill,minmax(8rem,1fr))] sm:grid-cols-[repeat(auto-fill,minmax(9.5rem,1fr))]" : "grid-cols-[repeat(auto-fill,minmax(9rem,1fr))] sm:grid-cols-[repeat(auto-fill,minmax(11rem,1fr))]"}`}
    >
      {children}
    </ul>
  );
}
