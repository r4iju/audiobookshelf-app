"use client";

import { List } from "lucide-react";
import { Button } from "@/components/ui/button";
import { useI18n } from "@/i18n/i18n";
import { useSettings, useSettingsStore } from "@/lib/settings/store";

/** The legacy bookshelf's grid or list switch, kept on this device. */
export function ListViewToggle() {
  const { t } = useI18n();
  const listView = useSettings().bookshelfListView;
  const update = useSettingsStore((state) => state.update);
  return (
    <Button
      size="icon"
      variant={listView ? "secondary" : "ghost"}
      aria-label={t("WebListView")}
      aria-pressed={listView}
      onClick={() => update({ bookshelfListView: !listView })}
    >
      <List aria-hidden className="size-5" />
    </Button>
  );
}
