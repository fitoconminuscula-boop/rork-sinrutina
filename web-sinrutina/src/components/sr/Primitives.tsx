import { X } from "lucide-react";
import {
  useCallback,
  useEffect,
  useRef,
  useState,
  type ButtonHTMLAttributes,
  type HTMLAttributes,
  type PointerEvent as ReactPointerEvent,
  type ReactNode,
} from "react";

import { useAppearance, useHaptics } from "@/sr/AppearanceProvider";
import { cn } from "@/lib/utils";

/**
 * One surface treatment for the whole app, so "Sin tarjetas", "Sutiles" and
 * "Separadas" stay consistent everywhere instead of only on the main screen.
 */
export function SRCard({ className, children, ...rest }: HTMLAttributes<HTMLDivElement>) {
  return (
    <div
      {...rest}
      className={cn("sr-card", className)}
      style={{ padding: "var(--sr-card-padding)", ...rest.style }}
    >
      {children}
    </div>
  );
}

interface ActionProps extends ButtonHTMLAttributes<HTMLButtonElement> {
  children: ReactNode;
}

/** Flat, solid and uniform. The shape option changes radius and height only. */
export function SRPrimaryButton({ className, children, onClick, ...rest }: ActionProps) {
  const haptics = useHaptics();
  return (
    <button
      {...rest}
      onClick={(event) => {
        haptics.light();
        onClick?.(event);
      }}
      className={cn("sr-primary-button", className)}
    >
      {children}
    </button>
  );
}

/** Always present, never loud: alternatives live at footnote weight. */
export function SRQuietButton({ className, children, onClick, ...rest }: ActionProps) {
  const haptics = useHaptics();
  return (
    <button
      {...rest}
      onClick={(event) => {
        haptics.light();
        onClick?.(event);
      }}
      className={cn("sr-quiet-button", className)}
    >
      {children}
    </button>
  );
}

export function SRSectionLabel({ children }: { children: ReactNode }) {
  return (
    <p className="text-[11px] font-semibold uppercase tracking-[0.08em] text-[var(--sr-secondary-ink)]">
      {children}
    </p>
  );
}

/**
 * One line of quiet context: a small symbol and a short sentence, optionally
 * tappable. It exists so context never needs a card of its own.
 */
export function SRQuietLine({
  icon,
  text,
  onClick,
}: {
  icon: ReactNode;
  text: string;
  onClick?: () => void;
}) {
  const haptics = useHaptics();
  const content = (
    <>
      <span className="shrink-0 [&>svg]:h-3.5 [&>svg]:w-3.5">{icon}</span>
      <span className="truncate">{text}</span>
    </>
  );
  const className =
    "inline-flex max-w-full items-center gap-1.5 rounded-full bg-[var(--sr-primary-soft)] px-3 py-1.5 text-[13px] font-medium text-[var(--sr-primary)]";

  if (!onClick) return <span className={className}>{content}</span>;
  return (
    <button
      type="button"
      onClick={() => {
        haptics.light();
        onClick();
      }}
      className={cn(className, "sr-pressable")}
    >
      {content}
    </button>
  );
}

/**
 * A sheet for everything that is not the dominant action. Progressive disclosure
 * is the whole point: details exist, but only on request.
 */
export function SRSheet({
  isOpen,
  onClose,
  title,
  children,
}: {
  isOpen: boolean;
  onClose: () => void;
  title: string;
  children: ReactNode;
}) {
  const { isStill } = useAppearance();
  const haptics = useHaptics();
  const panelRef = useRef<HTMLDivElement>(null);

  /** How far the finger has pulled the sheet down, in pixels. */
  const [drag, setDrag] = useState(0);
  const [isDragging, setIsDragging] = useState(false);
  const dragStart = useRef<number | null>(null);
  const isClosing = useRef(false);

  const close = useCallback(() => {
    if (isClosing.current) return;
    isClosing.current = true;
    onClose();
  }, [onClose]);

  useEffect(() => {
    if (!isOpen) {
      // Ready for the next time this sheet is opened.
      isClosing.current = false;
      setDrag(0);
      setIsDragging(false);
      return;
    }

    const onKey = (event: KeyboardEvent): void => {
      if (event.key === "Escape") close();
    };
    document.addEventListener("keydown", onKey);
    panelRef.current?.focus();
    return () => document.removeEventListener("keydown", onKey);
  }, [isOpen, close]);

  /**
   * The sheet follows the finger downwards, and meets resistance going up —
   * there is nothing above it to pull towards. Dragging starts only from the
   * handle and the title bar, so a list inside the sheet still scrolls normally.
   */
  const onPointerDown = (event: ReactPointerEvent<HTMLDivElement>): void => {
    if (isClosing.current) return;
    dragStart.current = event.clientY;
    setIsDragging(true);
    event.currentTarget.setPointerCapture(event.pointerId);
  };

  const onPointerMove = (event: ReactPointerEvent<HTMLDivElement>): void => {
    if (dragStart.current === null) return;
    const travel = event.clientY - dragStart.current;
    setDrag(travel > 0 ? travel : travel * 0.12);
  };

  const onPointerUp = (): void => {
    if (dragStart.current === null) return;
    dragStart.current = null;
    setIsDragging(false);

    // Far enough to mean it, or flicked hard enough to mean it.
    if (drag > 110) {
      haptics.soft();
      close();
      return;
    }
    setDrag(0);
  };

  if (!isOpen) return null;

  return (
    <div className="fixed inset-0 z-50 flex items-end justify-center sm:items-center">
      <button
        type="button"
        aria-label="Cerrar"
        onClick={close}
        className={cn("absolute inset-0 bg-black/30 backdrop-blur-[2px]", !isStill && "sr-fade-in")}
        // The dimming lifts as the sheet is pulled away, so the gesture is
        // reversible: you can see what you are going back to before letting go.
        style={{ opacity: Math.max(0, 1 - Math.max(0, drag) / 320) }}
      />
      <div
        ref={panelRef}
        role="dialog"
        aria-modal="true"
        aria-label={title}
        tabIndex={-1}
        className={cn(
          "relative flex max-h-[86dvh] w-full max-w-[560px] flex-col overflow-hidden rounded-t-[26px] bg-[var(--sr-elevated)] outline-none sm:rounded-[26px]",
          !isStill && drag === 0 && !isDragging && "sr-sheet-in"
        )}
        style={{
          transform: `translateY(${Math.max(0, drag)}px)`,
          transition: isDragging || isStill ? "none" : "transform var(--sr-duration-standard) var(--sr-ease-settle)",
          // Stay clear of the on-screen keyboard instead of hiding underneath it.
          marginBottom: "var(--sr-keyboard)",
        }}
      >
        <div
          className="shrink-0 cursor-grab touch-none active:cursor-grabbing"
          onPointerDown={onPointerDown}
          onPointerMove={onPointerMove}
          onPointerUp={onPointerUp}
          onPointerCancel={onPointerUp}
        >
          <div className="flex justify-center pt-2.5" aria-hidden="true">
            <span className="sr-grabber" />
          </div>
          <div className="flex items-center justify-between gap-3 px-5 pb-3 pt-3">
            <h2 className="text-[17px] font-semibold text-[var(--sr-ink)]">{title}</h2>
            <button
              type="button"
              onClick={close}
              aria-label="Cerrar"
              className="sr-pressable grid h-8 w-8 place-items-center rounded-full bg-[var(--sr-primary-soft)] text-[var(--sr-primary)]"
            >
              <X className="h-4 w-4" />
            </button>
          </div>
        </div>
        <div className="sr-scroll px-5 pb-[max(20px,env(safe-area-inset-bottom))]">{children}</div>
      </div>
    </div>
  );
}

/** A tappable row inside a sheet: one action, one line, nothing competing. */
export function SRSheetRow({
  icon,
  title,
  detail,
  tone = "normal",
  onClick,
}: {
  icon: ReactNode;
  title: string;
  detail?: string;
  tone?: "normal" | "quiet";
  onClick: () => void;
}) {
  const haptics = useHaptics();
  return (
    <button
      type="button"
      onClick={() => {
        haptics.light();
        onClick();
      }}
      className="sr-pressable flex w-full items-center gap-3 rounded-[var(--sr-row-radius)] px-3 py-3 text-left hover:bg-[var(--sr-primary-soft)]"
    >
      <span
        className={cn(
          "grid h-9 w-9 shrink-0 place-items-center rounded-full [&>svg]:h-[17px] [&>svg]:w-[17px]",
          tone === "quiet"
            ? "bg-[var(--sr-divider)] text-[var(--sr-secondary-ink)]"
            : "bg-[var(--sr-primary-soft)] text-[var(--sr-primary)]"
        )}
      >
        {icon}
      </span>
      <span className="min-w-0 flex-1">
        <span className="block text-[15px] font-medium text-[var(--sr-ink)]">{title}</span>
        {detail ? <span className="block text-[13px] text-[var(--sr-secondary-ink)]">{detail}</span> : null}
      </span>
    </button>
  );
}

/** A brief, unmistakable confirmation that a tap did something. */
export function SRFlashLine({ text }: { text: string }) {
  const { isStill } = useAppearance();
  return (
    <p
      className={cn(
        "flex items-center gap-2 text-[13px] text-[var(--sr-secondary-ink)]",
        !isStill && "sr-fade-in"
      )}
      role="status"
    >
      <span className="h-1.5 w-1.5 rounded-full bg-[var(--sr-mint)]" />
      {text}
    </p>
  );
}

/** Segmented choice used all over Ajustes. */
export function SRSegmented<T extends string>({
  options,
  value,
  onChange,
  label,
}: {
  options: { id: T; label: string }[];
  value: T;
  onChange: (id: T) => void;
  label: string;
}) {
  const haptics = useHaptics();
  return (
    <div role="radiogroup" aria-label={label} className="flex gap-1.5 rounded-[14px] bg-[var(--sr-divider)] p-1">
      {options.map((option) => {
        const isActive = option.id === value;
        return (
          <button
            key={option.id}
            type="button"
            role="radio"
            aria-checked={isActive}
            onClick={() => {
              haptics.light();
              onChange(option.id);
            }}
            className={cn(
              "sr-pressable flex-1 rounded-[10px] px-2 py-2 text-[13px] font-medium transition-colors",
              isActive
                ? "bg-[var(--sr-surface)] text-[var(--sr-ink)] shadow-[0_1px_3px_rgb(0_0_0_/_0.08)]"
                : "text-[var(--sr-secondary-ink)]"
            )}
          >
            {option.label}
          </button>
        );
      })}
    </div>
  );
}
