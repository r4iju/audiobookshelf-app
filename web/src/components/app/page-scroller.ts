"use client";

import { type RefObject, useEffect } from "react";
import { z } from "zod";

const STORAGE_KEY = "abs-web:v1:scroll";
/** How long a returning page may take to grow tall enough to reach its old place. */
const RESTORE_WINDOW_MS = 2000;

/** A reload or a return to an unloaded page is restored once, by the first scroller to mount. */
let loadRestored = false;

const here = () => location.pathname + location.search;

const storedSchema = z.record(z.string(), z.number()).catch({});

function readStored() {
  try {
    return new Map(
      Object.entries(storedSchema.parse(JSON.parse(sessionStorage.getItem(STORAGE_KEY) ?? "{}"))),
    );
  } catch {
    return new Map<string, number>();
  }
}

/**
 * The page scrolls in `scroller` instead of the window, so that its scrollbar ends above the player; the browser's
 * own restoration only covers the window. This keeps it: back, forward and reload return each address to where it
 * was left, following content that arrives after the route renders, until the user scrolls themselves.
 */
export function useScrollRestoration(scroller: RefObject<HTMLElement | null>, enabled: boolean) {
  // External system: the scroller's position, the history stack and session storage.
  useEffect(() => {
    const element = scroller.current;
    if (!enabled || !element) return;
    const positions = readStored();
    let restoring: { target: number; until: number } | null = null;
    let frame = 0;

    const apply = () => {
      if (!restoring) return;
      element.scrollTop = restoring.target;
      if (Math.abs(element.scrollTop - restoring.target) < 2 || performance.now() > restoring.until) {
        restoring = null;
        return;
      }
      frame = requestAnimationFrame(apply);
    };
    const restore = () => {
      cancelAnimationFrame(frame);
      restoring = { target: positions.get(here()) ?? 0, until: performance.now() + RESTORE_WINDOW_MS };
      frame = requestAnimationFrame(apply);
    };
    const cancel = () => {
      restoring = null;
      cancelAnimationFrame(frame);
    };
    // While a restore is pending the old page may still be showing, and its scroll events belong to it.
    const save = () => {
      if (!restoring) positions.set(here(), element.scrollTop);
    };
    const persist = () => sessionStorage.setItem(STORAGE_KEY, JSON.stringify(Object.fromEntries(positions)));

    // The "navigation" entry type only ever lists PerformanceNavigationTiming entries.
    const [entry] = performance.getEntriesByType("navigation") as PerformanceNavigationTiming[];
    if (!loadRestored && entry && entry.type !== "navigate") restore();
    loadRestored = true;

    element.addEventListener("scroll", save, { passive: true });
    window.addEventListener("popstate", restore);
    window.addEventListener("pagehide", persist);
    for (const type of ["wheel", "touchstart", "keydown", "pointerdown"] as const) {
      element.addEventListener(type, cancel, { passive: true });
    }
    return () => {
      cancel();
      persist();
      element.removeEventListener("scroll", save);
      window.removeEventListener("popstate", restore);
      window.removeEventListener("pagehide", persist);
      for (const type of ["wheel", "touchstart", "keydown", "pointerdown"] as const) {
        element.removeEventListener(type, cancel);
      }
    };
  }, [scroller, enabled]);
}

/** Keys that scroll the page in the browser, and the controls that keep them for themselves. */
const keepsKeys =
  "input, textarea, select, [contenteditable], dialog, [role=slider], [role=listbox], [role=menu]";
const keepsSpace = "button, summary, [role=button], [role=checkbox], [role=switch]";

/**
 * Page keys scroll the nearest scrolling box around the focus, which for the window's page was always the page. With
 * the focus outside the page's own box (on the body, the navigation or the dock) they would scroll nothing, so they
 * are passed on to it there, except where the focused control uses them itself.
 */
export function useKeyboardScrolling(scroller: RefObject<HTMLElement | null>, enabled: boolean) {
  // External system: the document's key presses and the scroller's position.
  useEffect(() => {
    const element = scroller.current;
    if (!enabled || !element) return;
    const onKey = (event: KeyboardEvent) => {
      if (event.defaultPrevented || event.altKey || event.ctrlKey || event.metaKey) return;
      if (event.shiftKey && event.key !== " ") return;
      const target = event.target instanceof Element ? event.target : null;
      if (target && (element.contains(target) || target.closest(keepsKeys))) return;
      if (event.key === " " && target?.closest(keepsSpace)) return;
      const page = element.clientHeight * 0.875;
      const top = {
        PageDown: element.scrollTop + page,
        PageUp: element.scrollTop - page,
        " ": element.scrollTop + (event.shiftKey ? -page : page),
        ArrowDown: element.scrollTop + 40,
        ArrowUp: element.scrollTop - 40,
        Home: 0,
        End: element.scrollHeight,
      }[event.key];
      if (top === undefined) return;
      event.preventDefault();
      element.scrollTo({ top });
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [scroller, enabled]);
}
