export type ModelOrigin = "Handy" | "Local" | "Custom";

export interface ModelEntry {
  id: string;
  displayName: string;
  path: string;
  sizeBytes: number;
  origin: ModelOrigin;
}

export interface DownloadPlan {
  id: string;
  url: string;
  filename: string;
  destinationDir: string;
}

export interface SegmentPayload {
  startMs: number;
  endMs: number;
  text: string;
}

export interface AppSettings {
  selectedModelId: string | null;
  shortcutMode: "toggle" | "pushToTalk" | "Toggle" | "PushToTalk";
  shortcutDisplay: string;
  vadThreshold: number;
  autoPaste: boolean;
  micDevice: string | null;
  language: string | null;
  onboardingDone: boolean;
}

export interface SileroStatus {
  available: boolean;
  path: string | null;
}

