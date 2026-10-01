"use client";

import { ChevronLeft, ChevronRight } from "lucide-react";
import { type PointerEvent, useEffect, useEffectEvent, useRef } from "react";
import { z } from "zod";
import { Button } from "@/components/ui/button";
import { useI18n } from "@/i18n/i18n";

interface Turns {
  next: () => void;
  previous: () => void;
}

const typing = (target: EventTarget | null) =>
  target instanceof HTMLElement &&
  (target.isContentEditable || /^(INPUT|TEXTAREA|SELECT)$/.test(target.tagName));

/** Arrow and page keys turn pages anywhere in the reader except while typing. */
export function usePageKeys(turns: Turns) {
  const onKey = useEffectEvent((event: KeyboardEvent) => {
    if (event.defaultPrevented || event.altKey || event.ctrlKey || event.metaKey || typing(event.target))
      return;
    if (event.key === "ArrowRight" || event.key === "PageDown") turns.next();
    else if (event.key === "ArrowLeft" || event.key === "PageUp") turns.previous();
    else return;
    event.preventDefault();
  });

  // External system: keys reach the window, not a focused element of the reader.
  useEffect(() => {
    const listener = (event: KeyboardEvent) => onKey(event);
    window.addEventListener("keydown", listener);
    return () => window.removeEventListener("keydown", listener);
  }, []);
}

/** A quick, mostly horizontal touch swipe of more than 60px turns the page, as in the legacy reader. */
export function useSwipe(turns: Turns) {
  const start = useRef<{ x: number; y: number; at: number } | null>(null);
  return {
    onPointerDown: (event: PointerEvent) => {
      start.current =
        event.pointerType === "mouse" ? null : { x: event.clientX, y: event.clientY, at: Date.now() };
    },
    onPointerUp: (event: PointerEvent) => {
      const from = start.current;
      start.current = null;
      if (!from || Date.now() - from.at >= 1000) return;
      const dx = event.clientX - from.x;
      if (Math.abs(dx) <= 60 || Math.abs(dx) <= Math.abs(event.clientY - from.y)) return;
      if (dx < 0) turns.next();
      else turns.previous();
    },
  };
}

const pageInput = z.coerce.number().int();

export function PageControls({
  page,
  pages,
  onGo,
}: {
  page: number;
  pages: number;
  onGo: (page: number) => void;
}) {
  const { t } = useI18n();
  return (
    <nav
      aria-label={t("WebReaderNavigation")}
      className="flex items-center justify-between gap-2 border-t border-line px-2 py-2 sm:px-4"
    >
      <Button
        variant="ghost"
        size="icon"
        aria-label={t("WebPreviousPage")}
        disabled={page <= 1}
        onClick={() => onGo(page - 1)}
      >
        <ChevronLeft aria-hidden className="size-5" />
      </Button>
      <form
        className="flex items-center gap-2 text-sm"
        action={(form) => {
          const parsed = pageInput.safeParse(form.get("page"));
          if (parsed.success) onGo(parsed.data);
        }}
      >
        <label className="sr-only" htmlFor="reader-page">
          {t("WebGoToPage")}
        </label>
        <input
          key={page}
          id="reader-page"
          name="page"
          type="number"
          inputMode="numeric"
          min={1}
          max={pages}
          defaultValue={page}
          className="w-16 rounded-lg border border-line bg-surface px-2 py-1 text-center tabular-nums focus-ring"
        />
        <output aria-live="polite" className="text-muted tabular-nums">
          {t("WebReaderPage", page, pages)}
        </output>
      </form>
      <Button
        variant="ghost"
        size="icon"
        aria-label={t("WebNextPage")}
        disabled={page >= pages}
        onClick={() => onGo(page + 1)}
      >
        <ChevronRight aria-hidden className="size-5" />
      </Button>
    </nav>
  );
}
