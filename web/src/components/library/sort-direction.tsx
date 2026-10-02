import { ArrowDownWideNarrow, ArrowUpNarrowWide } from "lucide-react";
import { useI18n } from "@/i18n/i18n";

/**
 * Ascending and descending as one segmented control. The chosen direction is filled and named at every width; the
 * other is named only where the toolbar has room.
 */
export function SortDirection({ desc, onChange }: { desc: boolean; onChange: (desc: boolean) => void }) {
  const { t } = useI18n();
  const choices = [
    { value: false, label: t("WebAscending"), Icon: ArrowUpNarrowWide },
    { value: true, label: t("WebDescending"), Icon: ArrowDownWideNarrow },
  ];
  return (
    <fieldset className="flex shrink-0 gap-0.5 rounded-xl border border-line bg-surface p-0.5">
      <legend className="sr-only">{t("WebSortDirection")}</legend>
      {choices.map(({ value, label, Icon }) => {
        const chosen = desc === value;
        return (
          <button
            key={label}
            type="button"
            aria-pressed={chosen}
            title={label}
            onClick={() => onChange(value)}
            className={`inline-flex min-h-9 items-center justify-center gap-1.5 rounded-lg px-2.5 text-sm transition-colors focus-ring ${chosen ? "bg-accent-strong font-semibold text-accent-fg" : "font-medium text-muted hover:bg-surface-2 hover:text-fg"}`}
          >
            <Icon aria-hidden className="size-4 shrink-0" />
            <span className={chosen ? "whitespace-nowrap" : "sr-only xl:not-sr-only xl:whitespace-nowrap"}>
              {label}
            </span>
          </button>
        );
      })}
    </fieldset>
  );
}
