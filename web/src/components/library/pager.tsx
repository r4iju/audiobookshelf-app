import { ChevronLeft, ChevronRight } from "lucide-react";
import Link from "next/link";
import { buttonClass } from "@/components/ui/button";
import { useI18n } from "@/i18n/i18n";

export function Pager({
  page,
  pages,
  hrefFor,
  pageLabel,
}: {
  page: number;
  pages: number;
  hrefFor: (page: number) => string;
  /** In place of "Page 2 of 5", where the number of pages is not known. */
  pageLabel?: string;
}) {
  const { t } = useI18n();
  if (pages <= 1) return null;
  const labels = {
    nav: t("WebPagination"),
    previous: t("WebPrevious"),
    next: t("WebNext"),
    pageOf: pageLabel ?? t("WebPageOf", page, pages),
  };
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
