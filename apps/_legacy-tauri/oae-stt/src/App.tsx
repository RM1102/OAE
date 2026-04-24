import { useMemo, useState } from "react";
import { useTranslation } from "react-i18next";
import { LiveTab } from "./components/LiveTab";
import { FileTab } from "./components/FileTab";
import { SettingsPanel } from "./components/SettingsPanel";
import { Onboarding } from "./components/Onboarding";

type Tab = "live" | "file" | "history" | "settings";

function App() {
  const { t } = useTranslation();
  const [tab, setTab] = useState<Tab>("live");
  const nav: { id: Tab; label: string }[] = useMemo(
    () => [
      { id: "live", label: t("nav.live") },
      { id: "file", label: t("nav.file") },
      { id: "history", label: t("nav.history") },
      { id: "settings", label: t("nav.settings") },
    ],
    [t],
  );

  return (
    <div className="h-full bg-zinc-900 text-zinc-100 flex">
      <aside className="w-44 border-r border-zinc-800 p-3 space-y-2">
        <h1 className="font-semibold mb-2">{t("app.title")}</h1>
        {nav.map((n) => (
          <button
            key={n.id}
            className={`w-full text-left px-2 py-1 rounded ${
              tab === n.id ? "bg-zinc-700" : "hover:bg-zinc-800"
            }`}
            onClick={() => setTab(n.id)}
          >
            {n.label}
          </button>
        ))}
      </aside>
      <main className="flex-1 p-4 space-y-3 overflow-auto">
        <Onboarding />
        {tab === "live" && <LiveTab />}
        {tab === "file" && <FileTab />}
        {tab === "settings" && <SettingsPanel />}
        {tab === "history" && (
          <p className="text-zinc-400 text-sm">History is stored in local JSONL for MVP.</p>
        )}
      </main>
    </div>
  );
}

export default App;
