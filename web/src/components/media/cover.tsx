"use client";

import { BookOpen } from "lucide-react";
import { useState } from "react";
import type { CoverShape } from "@/lib/abs/media";

const shapes: Record<CoverShape, string> = { book: "aspect-[1/1.6]", square: "aspect-square" };

/**
 * Every cover sits in a box of the library's shape so grids and shelves stay aligned whatever the image's own
 * proportions; mismatched art is contained over a blurred copy of itself. Missing or unloadable art becomes a
 * typographic placeholder of the same size, or just its icon when `compact` leaves no room for text or the
 * title is already printed beside the cover.
 */
export function Cover({
  src,
  title,
  subtitle,
  shape,
  missingLabel,
  compact = false,
  className = "",
}: {
  src: string | null;
  title: string;
  subtitle?: string;
  shape: CoverShape;
  missingLabel: string;
  compact?: boolean;
  className?: string;
}) {
  const [failedSrc, setFailedSrc] = useState<string | null>(null);
  const showImage = src !== null && failedSrc !== src;
  return (
    <div
      className={`relative w-full overflow-hidden rounded-xl bg-surface-2 shadow-sm ${shapes[shape]} ${className}`}
    >
      {showImage ? (
        <>
          <img
            src={src}
            alt=""
            aria-hidden
            loading="lazy"
            decoding="async"
            className="absolute inset-0 size-full scale-110 object-cover opacity-60 blur-xl"
          />
          <img
            src={src}
            alt=""
            loading="lazy"
            decoding="async"
            onError={() => setFailedSrc(src)}
            className="absolute inset-0 size-full object-contain"
          />
        </>
      ) : compact ? (
        <div className="@container absolute inset-0 flex items-center justify-center bg-gradient-to-br from-surface-3 to-surface-2">
          <BookOpen aria-hidden className="size-5 text-muted @[6rem]:size-10" />
          <span className="sr-only">{missingLabel}</span>
        </div>
      ) : (
        <div className="absolute inset-0 flex flex-col justify-between bg-gradient-to-br from-surface-3 to-surface-2 p-3">
          <BookOpen aria-hidden className="size-5 text-muted" />
          <span className="sr-only">{missingLabel}</span>
          <div aria-hidden className="min-w-0">
            <p className="line-clamp-4 text-sm leading-snug font-semibold break-words">{title}</p>
            {subtitle ? <p className="mt-1 line-clamp-2 text-xs text-muted">{subtitle}</p> : null}
          </div>
        </div>
      )}
    </div>
  );
}

export function ProgressBar({ value, label }: { value: number; label: string }) {
  const percent = Math.round(Math.min(1, Math.max(0, value)) * 100);
  return (
    <div
      role="progressbar"
      aria-label={label}
      aria-valuemin={0}
      aria-valuemax={100}
      aria-valuenow={percent}
      className="h-1 w-full overflow-hidden rounded-full bg-surface-3"
    >
      <div className="h-full rounded-full bg-accent" style={{ width: `${percent}%` }} />
    </div>
  );
}
