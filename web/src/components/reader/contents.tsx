"use client";

import { List, Settings2 } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Dialog } from "@/components/ui/dialog";
import { useI18n } from "@/i18n/i18n";

export interface Chapter {
  key: string;
  label: string;
  href: string;
  depth: number;
}

interface TocEntry {
  label: string;
  href: string;
  subitems?: TocEntry[] | undefined;
}

export function flattenToc(toc: readonly TocEntry[], depth = 0, parent = ""): Chapter[] {
  return toc.flatMap((entry, index) => {
    const key = `${parent}${index}`;
    return [
      { key, label: entry.label.trim(), href: entry.href, depth },
      ...flattenToc(entry.subitems ?? [], depth + 1, `${key}.`),
    ];
  });
}

export function ContentsDialog({
  chapters,
  onPick,
  onClose,
  title,
  current,
}: {
  chapters: Chapter[];
  onPick: (chapter: Chapter) => void;
  onClose: () => void;
  title?: string;
  /** The key of the entry being read. */
  current?: string;
}) {
  const { t } = useI18n();
  return (
    <Dialog open onClose={onClose} title={title ?? t("HeaderTableOfContents")}>
      {chapters.length ? (
        <ul className="-mx-2 flex max-h-[60vh] flex-col gap-0.5 overflow-y-auto">
          {chapters.map((chapter) => (
            <li key={chapter.key}>
              <button
                type="button"
                aria-current={chapter.key === current ? "page" : undefined}
                className="w-full truncate rounded-lg px-3 py-2 text-start text-sm hover:bg-surface-2 focus-ring aria-[current=page]:bg-accent/15 aria-[current=page]:font-medium"
                style={{ paddingInlineStart: `${0.75 + chapter.depth}rem` }}
                onClick={() => {
                  onClose();
                  onPick(chapter);
                }}
              >
                {chapter.label}
              </button>
            </li>
          ))}
        </ul>
      ) : (
        <p className="text-sm text-muted">{t("MessageNoChapters")}</p>
      )}
      <div className="flex justify-end">
        <Button variant="ghost" onClick={onClose}>
          {t("WebClose")}
        </Button>
      </div>
    </Dialog>
  );
}

export function BookControls({
  status,
  onContents,
  onSettings,
}: {
  status: string | null;
  onContents: () => void;
  onSettings: () => void;
}) {
  const { t } = useI18n();
  return (
    <div className="flex items-center gap-1">
      <Button variant="ghost" size="icon" aria-label={t("HeaderTableOfContents")} onClick={onContents}>
        <List aria-hidden className="size-5" />
      </Button>
      <output aria-live="polite" className="min-w-32 text-center text-sm text-muted tabular-nums">
        {status}
      </output>
      <Button variant="ghost" size="icon" aria-label={t("WebReaderSettings")} onClick={onSettings}>
        <Settings2 aria-hidden className="size-5" />
      </Button>
    </div>
  );
}
