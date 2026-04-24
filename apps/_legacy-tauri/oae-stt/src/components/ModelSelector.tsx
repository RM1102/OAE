import { useEffect, useState } from "react";
import { useTranslation } from "react-i18next";
import { commands, events } from "../lib/tauri";
import type { ModelEntry } from "../lib/types";
import { useSettings } from "../hooks/useSettings";

export function ModelSelector() {
  const { t } = useTranslation();
  const { settings, update } = useSettings();
  const [models, setModels] = useState<ModelEntry[]>([]);
  const [loading, setLoading] = useState(false);

  const refresh = async () => {
    setModels(await commands.refreshModels());
  };

  useEffect(() => {
    void refresh();
    let un: (() => void) | null = null;
    void events.onModelsChanged(() => void refresh()).then((u) => (un = u));
    return () => {
      if (un) void un();
    };
  }, []);

  useEffect(() => {
    if (!settings || settings.selectedModelId || models.length === 0) return;
    const preferred =
      models.find((m) => m.origin === "Handy") ??
      models.find((m) => m.origin === "Local") ??
      models[0];
    void update({ selectedModelId: preferred.id });
  }, [settings, models, update]);

  const selected = settings?.selectedModelId ?? "";

  return (
    <div className="space-y-2">
      <label className="text-sm text-zinc-300">{t("models.title")}</label>
      <div className="flex gap-2">
        <select
          className="bg-zinc-900 border border-zinc-700 rounded px-2 py-1 flex-1"
          value={selected}
          onChange={(e) => void update({ selectedModelId: e.target.value || null })}
        >
          {models.map((m) => (
            <option key={m.id} value={m.id}>
              {m.displayName} ({m.origin})
            </option>
          ))}
        </select>
        <button
          className="px-3 py-1 rounded bg-zinc-800 hover:bg-zinc-700"
          onClick={() => void commands.openOwnModelsDir()}
        >
          {t("models.openFolder")}
        </button>
      </div>
      {models.length === 0 && (
        <div className="text-sm text-zinc-400 space-y-2">
          <p>No models found. Download one:</p>
          <div className="flex flex-wrap gap-2">
            {["whisper-small", "whisper-medium", "whisper-turbo", "whisper-large"].map((id) => (
              <button
                key={id}
                disabled={loading}
                className="px-2 py-1 rounded bg-emerald-700 hover:bg-emerald-600 disabled:opacity-50"
                onClick={async () => {
                  setLoading(true);
                  try {
                    await commands.downloadModel(id);
                    await refresh();
                  } finally {
                    setLoading(false);
                  }
                }}
              >
                {id.replace("whisper-", "")}
              </button>
            ))}
          </div>
        </div>
      )}
    </div>
  );
}

