import { CalendarDays, Leaf, Plus, Settings, Target } from "lucide-react";

import { useHaptics } from "@/sr/AppearanceProvider";
import { cn } from "@/lib/utils";

/**
 * Exactly four destinations. There is no tab for tools, no dashboard of
 * functions: everything else appears inside an action, when it is relevant.
 */
export type AppTab = "now" | "after" | "someday" | "settings";

const TABS: { id: AppTab; label: string; icon: typeof Target }[] = [
  { id: "now", label: "Ahora", icon: Target },
  { id: "after", label: "Después", icon: CalendarDays },
  { id: "someday", label: "Algún día", icon: Leaf },
  { id: "settings", label: "Ajustes", icon: Settings },
];

export function TabBar({
  active,
  onSelect,
  onCapture,
}: {
  active: AppTab;
  onSelect: (tab: AppTab) => void;
  onCapture: () => void;
}) {
  const haptics = useHaptics();

  return (
    <div className="pointer-events-none fixed inset-x-0 bottom-0 z-40 flex justify-center px-3 pb-[max(12px,env(safe-area-inset-bottom))]">
      <div className="pointer-events-auto flex w-full max-w-[460px] items-center gap-2">
        <nav
          aria-label="Secciones"
          className="flex flex-1 items-center justify-around rounded-[22px] border border-[var(--sr-divider)] bg-[var(--sr-elevated)]/92 px-1.5 py-1.5 shadow-[0_8px_28px_rgb(0_0_0_/_0.10)] backdrop-blur-xl"
        >
          {TABS.map((tab) => {
            const Icon = tab.icon;
            const isActive = tab.id === active;
            return (
              <button
                key={tab.id}
                type="button"
                onClick={() => {
                  haptics.light();
                  onSelect(tab.id);
                }}
                aria-current={isActive ? "page" : undefined}
                className={cn(
                  "sr-pressable flex min-w-[56px] flex-col items-center gap-1 rounded-[16px] px-2 py-1.5 transition-colors",
                  isActive ? "text-[var(--sr-primary)]" : "text-[var(--sr-secondary-ink)]"
                )}
                style={{ backgroundColor: isActive ? "var(--sr-primary-soft)" : "transparent" }}
              >
                <Icon className="h-[19px] w-[19px]" strokeWidth={isActive ? 2.4 : 1.9} />
                <span className="text-[10.5px] font-medium leading-none">{tab.label}</span>
              </button>
            );
          })}
        </nav>

        <button
          type="button"
          onClick={() => {
            haptics.soft();
            onCapture();
          }}
          aria-label="Capturar algo pendiente"
          className="sr-pressable grid h-[58px] w-[58px] shrink-0 place-items-center rounded-full shadow-[0_8px_24px_rgb(0_0_0_/_0.16)]"
          style={{ backgroundColor: "var(--sr-primary)", color: "var(--sr-on-primary)" }}
        >
          <Plus className="h-6 w-6" strokeWidth={2.4} />
        </button>
      </div>
    </div>
  );
}
