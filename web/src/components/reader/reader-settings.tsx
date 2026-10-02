"use client";

import { useState } from "react";
import { z } from "zod";
import { Button } from "@/components/ui/button";
import { Dialog } from "@/components/ui/dialog";
import { TextField } from "@/components/ui/field";
import { SelectField } from "@/components/ui/select";
import { useI18n } from "@/i18n/i18n";
import {
  type ReaderNumber,
  type ReaderSettings,
  readerLimits,
  readerNumber,
  readerSettingsSchema,
  useSettings,
  useSettingsStore,
} from "@/lib/settings/store";

/** Changes apply as they are made so the book behind the dialog shows them. */
export function ReaderSettingsDialog({ onClose, paged }: { onClose: () => void; paged: boolean }) {
  const { t } = useI18n();
  const reader = useSettings().reader;
  const update = useSettingsStore((state) => state.update);
  const change = (patch: Partial<ReaderSettings>) => update({ reader: { ...reader, ...patch } });
  const { shape } = readerSettingsSchema;

  return (
    <Dialog open onClose={onClose} title={t("HeaderEreaderSettings")}>
      <div className="grid gap-4 sm:grid-cols-2">
        <SelectField
          label={t("LabelTheme")}
          value={reader.theme}
          options={[
            { value: "dark", label: t("LabelThemeDark") },
            { value: "black", label: t("LabelThemeBlack") },
            { value: "light", label: t("LabelThemeLight") },
          ]}
          onChange={(theme) => change({ theme: shape.theme.parse(theme) })}
        />
        <SelectField
          label={t("LabelFontFamily")}
          value={reader.font}
          options={[
            { value: "serif", label: t("LabelFontFamilySerif") },
            { value: "sans-serif", label: t("LabelFontFamilySans") },
          ]}
          onChange={(font) => change({ font: shape.font.parse(font) })}
        />
        <NumberSetting
          name="fontScale"
          label={t("LabelFontScale")}
          value={reader.fontScale}
          onValid={(fontScale) => change({ fontScale })}
        />
        <NumberSetting
          name="lineSpacing"
          label={t("LabelLineSpacing")}
          value={reader.lineSpacing}
          onValid={(lineSpacing) => change({ lineSpacing })}
        />
        <NumberSetting
          name="textStroke"
          label={t("LabelFontBoldness")}
          value={reader.textStroke}
          onValid={(textStroke) => change({ textStroke })}
        />
        {paged ? (
          <SelectField
            label={t("LabelLayout")}
            value={reader.spread}
            options={[
              { value: "none", label: t("LabelLayoutSinglePage") },
              { value: "auto", label: t("LabelLayoutAuto") },
            ]}
            onChange={(spread) => change({ spread: shape.spread.parse(spread) })}
          />
        ) : null}
      </div>
      <div className="flex justify-end">
        <Button variant="ghost" onClick={onClose}>
          {t("WebClose")}
        </Button>
      </div>
    </Dialog>
  );
}

function NumberSetting({
  name,
  label,
  value,
  onValid,
}: {
  name: ReaderNumber;
  label: string;
  value: number;
  onValid: (value: number) => void;
}) {
  const { t } = useI18n();
  const [invalid, setInvalid] = useState(false);
  const { min, max, step } = readerLimits[name];
  return (
    <TextField
      label={label}
      type="number"
      inputMode="numeric"
      min={min}
      max={max}
      step={step}
      defaultValue={value}
      aria-invalid={invalid}
      help={invalid ? t("WebNumberRange", min, max) : undefined}
      onChange={(event) => {
        const parsed = z.coerce
          .number()
          .pipe(readerNumber(name))
          .safeParse(event.target.value === "" ? undefined : event.target.value);
        setInvalid(!parsed.success);
        if (parsed.success) onValid(parsed.data);
      }}
    />
  );
}
