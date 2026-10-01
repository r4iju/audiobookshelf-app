import { z } from "zod";
import { create } from "zustand";
import { isLanguageCode, type LanguageCode } from "@/i18n/languages";
import { readStored, writeStored } from "@/lib/storage/local";

const KEY = "abs-web:v1:settings";

// Allowed values mirror the legacy client (store/globals.js, PlaybackSpeedModal, SleepTimerModal).
export const jumpTimes = [5, 10, 15, 30, 60, 120, 300] as const;
export const ratePresets = [0.5, 1, 1.2, 1.5, 1.7, 2, 3] as const;
export const sleepPresetsMinutes = [5, 10, 15, 30, 45, 60, 90] as const;

const jump = z.number().refine((value) => (jumpTimes as readonly number[]).includes(value));

export const readerSettingsSchema = z.object({
  theme: z.enum(["dark", "black", "light"]).catch("dark"),
  font: z.enum(["serif", "sans-serif"]).catch("serif"),
  fontScale: z.number().min(5).max(300).catch(100),
  lineSpacing: z.number().min(100).max(300).catch(115),
  textStroke: z.number().min(0).max(300).catch(0),
  spread: z.enum(["auto", "none"]).catch("auto"),
});
export type ReaderSettings = z.infer<typeof readerSettingsSchema>;

export const settingsSchema = z.object({
  language: z
    .string()
    .nullable()
    .transform((value): LanguageCode | null => (isLanguageCode(value) ? value : null))
    .catch(null),
  theme: z.enum(["system", "dark", "black", "light"]).catch("dark"),
  reduceMotion: z.boolean().catch(false),
  jumpForwardTime: jump.catch(10),
  jumpBackwardsTime: jump.catch(10),
  playbackRate: z.number().min(0.5).max(10).catch(1),
  /** Milliseconds; 0 means end of chapter, as in the legacy sleepTimerLength setting. */
  sleepTimerLength: z.number().min(0).catch(900_000),
  disableAutoRewind: z.boolean().catch(false),
  disableSleepTimerFadeOut: z.boolean().catch(false),
  useChapterTrack: z.boolean().catch(false),
  useTotalTrack: z.boolean().catch(true),
  scaleElapsedTimeBySpeed: z.boolean().catch(true),
  bookshelfView: z.enum(["grid", "list"]).catch("grid"),
  collapseSeries: z.boolean().catch(false),
  podcastEpisodesOrderBy: z
    .enum(["publishedAt", "title", "season", "episode", "filename"])
    .catch("publishedAt"),
  podcastEpisodesOrderDesc: z.boolean().nullable().catch(null),
  podcastEpisodesFilterBy: z.enum(["all", "incomplete", "inProgress", "complete"]).catch("incomplete"),
  reader: readerSettingsSchema.catch(readerSettingsSchema.parse({})),
});
export type Settings = z.infer<typeof settingsSchema>;

export const defaultSettings: Settings = settingsSchema.parse({ language: null, reader: {} });

interface SettingsStore {
  settings: Settings;
  hydrated: boolean;
  update: (change: Partial<Settings>) => void;
  hydrate: () => void;
}

export const useSettingsStore = create<SettingsStore>()((set, get) => ({
  settings: defaultSettings,
  hydrated: false,
  update: (change) => {
    const settings = { ...get().settings, ...change };
    writeStored(KEY, settings);
    set({ settings });
  },
  hydrate: () => {
    const stored = readStored(KEY, z.record(z.string(), z.unknown()));
    set({ settings: settingsSchema.parse({ ...defaultSettings, ...stored }), hydrated: true });
  },
}));

export const SETTINGS_STORAGE_KEY = KEY;

export function useSettings() {
  return useSettingsStore((state) => state.settings);
}
