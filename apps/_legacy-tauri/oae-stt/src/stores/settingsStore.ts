import { create } from "zustand";
import type { AppSettings } from "../lib/types";
import { commands } from "../lib/tauri";

type State = {
  settings: AppSettings | null;
  load: () => Promise<void>;
  update: (patch: Partial<AppSettings>) => Promise<void>;
};

export const useSettingsStore = create<State>((set, get) => ({
  settings: null,
  load: async () => {
    const settings = await commands.getSettings();
    set({ settings });
  },
  update: async (patch) => {
    const current = get().settings;
    if (!current) return;
    const merged = { ...current, ...patch } as AppSettings;
    await commands.saveSettings(merged);
    set({ settings: merged });
  },
}));

