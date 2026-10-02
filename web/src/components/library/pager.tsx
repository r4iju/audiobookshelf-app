import { ChevronLeft, ChevronRight } from "lucide-react";
import Link from "next/link";
import { buttonClass } from "@/components/ui/button";

export function Pager({
  page,
  pages,
  hrefFor,
  labels,
}: {
  page: number;
  pages: number;
  hrefFor: (page: number) => string;
  labels: { nav: string; previous: string; next: string; pageOf: string };
}) {
  if (pages <= 1) return null;
  return (
    <nav aria-label={labels.nav} className="flex items-center justify-center gap-3">
      {page > 1 ? (
        <Link href={hrefFor(page - 1)} className={buttonClass("secondary", "sm")} rel="prev">
          <ChevronLeft aria-hidden className="size-4 rtl:rotate-180" />
          {labels.previous}
        </Link>
      ) : null}
      <p className="text-sm text-muted tabular-nums">{labels.pageOf}</p>
      {page < pages ? (
        <Link href={hrefFor(page + 1)} className={buttonClass("secondary", "sm")} rel="next">
          {labels.next}
          <ChevronRight aria-hidden className="size-4 rtl:rotate-180" />
        </Link>
      ) : null}
    </nav>
  );
}
