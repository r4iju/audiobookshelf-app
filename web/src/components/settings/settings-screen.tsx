"use client";

import { Check, Copy, LogOut } from "lucide-react";
import { useRouter } from "next/navigation";
import { type ReactNode, useEffect, useId, useState } from "react";
import { z } from "zod";
import { Button } from "@/components/ui/button";
import { SelectField, TextField, Toggle } from "@/components/ui/field";
import { useI18n } from "@/i18n/i18n";
import { isLanguageCode, languages } from "@/i18n/languages";
import { clientVersion } from "@/lib/device";
import { useSession, useSessionStore } from "@/lib/session/store";
import { jumpTimes, settingsSchema, useSettings, useSettingsStore } from "@/lib/settings/store";

const jumpChoice = z.coerce.number().pipe(settingsSchema.shape.jumpForwardTime.unwrap());

function Section({ title, children }: { title: string; children: ReactNode }) {
  const id = useId();
  return (
    <section aria-labelledby={id} className="flex flex-col gap-3 rounded-[var(--radius-card)] bg-surface p-5">
      <h2 id={id} className="text-sm font-semibold tracking-wide text-muted uppercase">
        {title}
      </h2>
      {children}
    </section>
  );
}

export function SettingsScreen() {
  const { t } = useI18n();
  const settings = useSettings();
  const update = useSettingsStore((state) => state.update);

  return (
    <div className="mx-auto flex w-full max-w-2xl flex-col gap-6">
      <h1 className="text-2xl font-bold">{t("HeaderSettings")}</h1>

      <Section title={t("HeaderUserInterfaceSettings")}>
        <div className="grid gap-4 sm:grid-cols-2">
          <SelectField
            label={t("LabelTheme")}
            value={settings.theme}
            onChange={(event) => update({ theme: settingsSchema.shape.theme.parse(event.target.value) })}
          >
            <option value="system">{t("WebThemeSystem")}</option>
            <option value="dark">{t("LabelThemeDark")}</option>
            <option value="black">{t("LabelThemeBlack")}</option>
            <option value="light">{t("LabelThemeLight")}</option>
          </SelectField>
          <SelectField
            label={t("LabelLanguage")}
            value={settings.language ?? ""}
            onChange={(event) =>
              update({ language: isLanguageCode(event.target.value) ? event.target.value : null })
            }
          >
            <option value="">{t("WebLanguageServerDefault")}</option>
            {Object.entries(languages).map(([code, name]) => (
              <option key={code} value={code} lang={code}>
                {name}
              </option>
            ))}
          </SelectField>
        </div>
        <Toggle
          label={t("WebReduceMotion")}
          checked={settings.reduceMotion}
          onChange={(event) => update({ reduceMotion: event.target.checked })}
        />
      </Section>

      <Section title={t("HeaderPlaybackSettings")}>
        <div className="grid gap-4 sm:grid-cols-2">
          <SelectField
            label={t("LabelJumpBackwardsTime")}
            value={settings.jumpBackwardsTime}
            onChange={(event) => update({ jumpBackwardsTime: jumpChoice.parse(event.target.value) })}
          >
            {jumpTimes.map((seconds) => (
              <option key={seconds} value={seconds}>
                {seconds} s
              </option>
            ))}
          </SelectField>
          <SelectField
            label={t("LabelJumpForwardsTime")}
            value={settings.jumpForwardTime}
            onChange={(event) => update({ jumpForwardTime: jumpChoice.parse(event.target.value) })}
          >
            {jumpTimes.map((seconds) => (
              <option key={seconds} value={seconds}>
                {seconds} s
              </option>
            ))}
          </SelectField>
        </div>
        <Toggle
          label={t("LabelDisableAutoRewind")}
          help={t("WebAutoRewindHelp")}
          checked={settings.disableAutoRewind}
          onChange={(event) => update({ disableAutoRewind: event.target.checked })}
        />
        <Toggle
          label={t("LabelAllowSeekingOnMediaControls")}
          checked={settings.allowSeekingOnMediaControls}
          onChange={(event) => update({ allowSeekingOnMediaControls: event.target.checked })}
        />
      </Section>

      <Section title={t("HeaderSleepTimerSettings")}>
        <Toggle
          label={t("LabelDisableAudioFadeOut")}
          checked={settings.disableSleepTimerFadeOut}
          onChange={(event) => update({ disableSleepTimerFadeOut: event.target.checked })}
        />
      </Section>

      <AccountSection />

      <Section title={t("WebBrowserLimits")}>
        <p className="text-sm">{t("WebBrowserLimitsBody")}</p>
        <p className="text-sm text-muted">{t("WebOfflineDownloadsUnavailable")}</p>
      </Section>

      <DiagnosticsSection />
    </div>
  );
}

function AccountSection() {
  const { t } = useI18n();
  const session = useSession();
  const signOut = useSessionStore((state) => state.signOut);
  const router = useRouter();
  if (session.phase !== "signed-in") return null;
  const { connection } = session;
  return (
    <Section title={t("HeaderAccount")}>
      <div className="grid gap-4 sm:grid-cols-2">
        <TextField label={t("LabelHost")} value={connection.serverUrl} readOnly />
        <TextField label={t("LabelUsername")} value={connection.username} readOnly />
      </div>
      {connection.serverVersion ? (
        <p className="text-sm text-muted">{t("WebServerVersion", connection.serverVersion)}</p>
      ) : null}
      <div className="flex justify-end">
        <Button
          onClick={() => {
            signOut();
            router.replace("/connect");
          }}
        >
          {t("ButtonSwitchServerUser")}
          <LogOut aria-hidden className="size-4" />
        </Button>
      </div>
    </Section>
  );
}

const audioFormats = {
  MP3: "audio/mpeg",
  "M4A/M4B (AAC)": 'audio/mp4; codecs="mp4a.40.2"',
  FLAC: "audio/flac",
  "Ogg Vorbis": 'audio/ogg; codecs="vorbis"',
  Opus: 'audio/ogg; codecs="opus"',
  HLS: "application/vnd.apple.mpegurl",
};

interface BrowserFacts {
  userAgent: string;
  languages: string;
  timeZone: string;
  online: boolean;
  formats: string;
  mediaSession: boolean;
  storage: string;
}

/** What this browser can do. Nothing here signs in, so the report is safe to paste into a bug report. */
async function browserFacts(): Promise<BrowserFacts> {
  const audio = document.createElement("audio");
  const estimate = await navigator.storage?.estimate?.().catch(() => null);
  const persisted = await navigator.storage?.persisted?.().catch(() => false);
  return {
    userAgent: navigator.userAgent,
    languages: navigator.languages.join(", "),
    timeZone: Intl.DateTimeFormat().resolvedOptions().timeZone,
    online: navigator.onLine,
    formats: Object.entries(audioFormats)
      .map(([name, type]) => `${name} ${audio.canPlayType(type) || "no"}`)
      .join(", "),
    mediaSession: "mediaSession" in navigator,
    storage: estimate
      ? `${Math.round((estimate.usage ?? 0) / 1024)} KiB of ${Math.round((estimate.quota ?? 0) / 1048576)} MiB${persisted ? ", persistent" : ""}`
      : "unknown",
  };
}

function DiagnosticsSection() {
  const { t } = useI18n();
  const session = useSession();
  const [facts, setFacts] = useState<BrowserFacts | null>(null);
  const [copied, setCopied] = useState<"no" | "yes" | "failed">("no");

  // External system: the browser reports its capabilities and storage asynchronously.
  useEffect(() => {
    let current = true;
    void browserFacts().then((found) => current && setFacts(found));
    return () => {
      current = false;
    };
  }, []);

  const connection = session.phase === "signed-in" ? session.connection : null;
  // The details stay in English so whoever reads a pasted report can, whatever language the reporter uses.
  const lines = [
    t("WebClientVersion", clientVersion),
    connection ? `Server ${connection.serverUrl}` : null,
    connection?.serverVersion ? t("WebServerVersion", connection.serverVersion) : null,
    ...(facts
      ? [
          `User agent ${facts.userAgent}`,
          `Languages ${facts.languages}`,
          `Time zone ${facts.timeZone}`,
          `Online ${facts.online ? "yes" : "no"}`,
          `Audio ${facts.formats}`,
          `Media controls ${facts.mediaSession ? "yes" : "no"}`,
          `Storage ${facts.storage}`,
        ]
      : []),
  ].filter((line) => line !== null);
  const report = lines.join("\n");

  return (
    <Section title={t("WebDiagnostics")}>
      <pre className="overflow-x-auto rounded-xl bg-surface-2 p-3 text-xs whitespace-pre-wrap break-all">
        {report}
      </pre>
      <div className="flex items-center justify-end gap-3">
        <p role="status" className={`text-sm ${copied === "failed" ? "text-danger" : "text-muted"}`}>
          {copied === "yes" ? t("WebCopied") : copied === "failed" ? t("WebCopyFailed") : null}
        </p>
        <Button
          onClick={() =>
            void navigator.clipboard.writeText(report).then(
              () => setCopied("yes"),
              () => setCopied("failed"),
            )
          }
        >
          {copied === "yes" ? (
            <Check aria-hidden className="size-4" />
          ) : (
            <Copy aria-hidden className="size-4" />
          )}
          {t("WebCopyDiagnostics")}
        </Button>
      </div>
    </Section>
  );
}
