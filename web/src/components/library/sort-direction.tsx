import { ArrowDownWideNarrow, ArrowUpNarrowWide } from "lucide-react";
import { Button } from "@/components/ui/button";
import { useI18n } from "@/i18n/i18n";

/** Ascending and descending as one segmented control; the words show only where the toolbar has room. */
export function SortDirection({ desc, onChange }: { desc: boolean; onChange: (desc: boolean) => void }) {
  const { t } = useI18n();
  const choices = [
    { value: false, label: t("WebAscending"), Icon: ArrowUpNarrowWide },
    { value: true, label: t("WebDescending"), Icon: ArrowDownWideNarrow },
  ];
  return (
    <fieldset className="flex shrink-0 rounded-xl bg-surface-2 p-1">
      <legend className="sr-only">{t("WebSortDirection")}</legend>
      {choices.map(({ value, label, Icon }) => (
        <Button
          key={label}
          size="sm"
          variant={desc === value ? "secondary" : "ghost"}
          aria-pressed={desc === value}
          title={label}
          onClick={() => onChange(value)}
        >
          <Icon aria-hidden className="size-4" />
          <span className="sr-only xl:not-sr-only">{label}</span>
        </Button>
      ))}
    </fieldset>
  );
}
