import { useEffect, useState } from "react";
import { useTranslation } from "react-i18next";
import { commands } from "../lib/tauri";
import { useSettings } from "../hooks/useSettings";
import { ModelSelector } from "./ModelSelector";

export function SettingsPanel() {
  const { t } = useTranslation();
  const { settings, update } = useSettings();
  const [mics, setMics] = useState<string[]>([]);

  useEffect(() => {
    void commands.listMics().then(setMics);
  }, []);

  if (!settings) return null;

  return (
    <div className="space-y-4">
      <ModelSelector />

      <div className="space-y-2">
        <label className="text-sm text-zinc-300">{t("settings.mic")}</label>
        <div className="flex gap-2">
          <select
            className="bg-zinc-900 border border-zinc-700 rounded px-2 py-1 flex-1"
            value={settings.micDevice ?? ""}
            onChange={(e) => void update({ micDevice: e.target.value || null })}
          >
            <option value="">Default</option>
            {mics.map((m) => (
              <option key={m} value={m}>
                {m}
              </option>
            ))}
          </select>
          <button
            className="px-3 py-1 rounded bg-zinc-800 hover:bg-zinc-700"
            onClick={async () => setMics(await commands.listMics())}
          >
            {t("settings.refreshMics")}
          </button>
        </div>
      </div>

      <div className="space-y-2">
        <label className="text-sm text-zinc-300">{t("settings.vadThreshold")}</label>
        <input
          type="range"
          min={0.3}
          max={0.9}
          step={0.01}
          value={settings.vadThreshold}
          onChange={(e) => void update({ vadThreshold: Number(e.target.value) })}
          className="w-full"
        />
        <p className="text-xs text-zinc-500">{settings.vadThreshold.toFixed(2)}</p>
      </div>

      <label className="flex gap-2 items-center text-sm">
        <input
          type="checkbox"
          checked={settings.autoPaste}
          onChange={(e) => void update({ autoPaste: e.target.checked })}
        />
        {t("settings.autoPaste")}
      </label>
    </div>
  );
}

