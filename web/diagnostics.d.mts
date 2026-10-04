export function readiness(directory: string): Promise<{
  ready: boolean;
  issues: string[];
  tools: {
    ffmpeg: { available: boolean; version: string | null };
    ffprobe: { available: boolean; version: string | null };
  };
  storage: { writable: boolean; freeBytes: number; databaseBytes: number };
}>;
