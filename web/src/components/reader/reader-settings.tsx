"use client";

import { useState } from "react";
import { z } from "zod";
import { Button } from "@/components/ui/button";
import { Dialog } from "@/components/ui/dialog";
import { SelectField, TextField } from "@/components/ui/field";
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
    <Dialog open onClose={onClose} title={t("WebReaderSettings")}>
      <div className="grid gap-4 sm:grid-cols-2">
        <SelectField
          label={t("LabelTheme")}
          value={reader.theme}
          onChange={(event) => change({ theme: shape.theme.parse(event.target.value) })}
        >
          <option value="dark">{t("LabelThemeDark")}</option>
          <option value="black">{t("LabelThemeBlack")}</option>
          <option value="light">{t("LabelThemeLight")}</option>
        </SelectField>
        <SelectField
          label={t("LabelFontFamily")}
          value={reader.font}
          onChange={(event) => change({ font: shape.font.parse(event.target.value) })}
        >
          <option value="serif">{t("LabelFontFamilySerif")}</option>
          <option value="sans-serif">{t("LabelFontFamilySans")}</option>
        </SelectField>
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
            onChange={(event) => change({ spread: shape.spread.parse(event.target.value) })}
          >
            <option value="none">{t("LabelLayoutSinglePage")}</option>
            <option value="auto">{t("LabelLayoutAuto")}</option>
          </SelectField>
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
