"use client";

import { useEffect } from "react";

const appName = "Leafwake";

/**
 * Names each page after its main heading, which is already in the reader's language and follows the page's data as
 * it loads. External system: the document's title, which Next.js also sets on navigation, so it is watched too.
 */
export function useHeadingTitle() {
  useEffect(() => {
    const sync = () => {
      const heading = document.querySelector("#main h1")?.textContent?.trim();
      const title = heading ? `${heading} · ${appName}` : appName;
      if (document.title !== title) document.title = title;
    };
    sync();
    const observer = new MutationObserver(sync);
    observer.observe(document.documentElement, { subtree: true, childList: true, characterData: true });
    return () => observer.disconnect();
  }, []);
}
