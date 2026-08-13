import { ChevronUp } from "lucide-react";
import { useCallback, useEffect, useRef, useState } from "react";

import { SRLogo } from "./SRMark";
import { useAppearance, useHaptics } from "@/sr/AppearanceProvider";
import { cn } from "@/lib/utils";

/**
 * The first thing the person sees, and the shortest thing they see.
 *
 * Same rules as the iPhone version: it never lasts longer than the preparation
 * it covers, it is never a gate, and it only offers the swipe hint if the wait
 * turns out to be real.
 */
export function LaunchScreen({ onFinished }: { onFinished: () => void }) {
  const { isStill } = useAppearance();
  const haptics = useHaptics();

  const [hasEntered, setHasEntered] = useState(false);
  const [showsHint, setShowsHint] = useState(false);
  const [offset, setOffset] = useState(0);
  const isLeaving = useRef(false);
  const dragStart = useRef<number | null>(null);

  const leave = useCallback(() => {
    if (isLeaving.current) return;
    isLeaving.current = true;
    haptics.soft();

    if (isStill) {
      onFinished();
      return;
    }
    setOffset(-(window.innerHeight + 120));
    window.setTimeout(onFinished, 420);
  }, [haptics, isStill, onFinished]);

  useEffect(() => {
    const timers: number[] = [];
    if (isStill) {
      setHasEntered(true);
    } else {
      timers.push(window.setTimeout(() => setHasEntered(true), 20));
    }
    // If we are still here, the wait is real and worth offering a way out of.
    timers.push(window.setTimeout(() => setShowsHint(true), 1100));
    // A last resort: this screen is not allowed to hold anyone hostage.
    timers.push(window.setTimeout(leave, 2600));
    return () => timers.forEach(window.clearTimeout);
  }, [isStill, leave]);

  const onPointerDown = (event: React.PointerEvent<HTMLDivElement>): void => {
    if (isLeaving.current) return;
    dragStart.current = event.clientY;
  };

  const onPointerMove = (event: React.PointerEvent<HTMLDivElement>): void => {
    if (dragStart.current === null || isLeaving.current) return;
    const translation = event.clientY - dragStart.current;
    // Up follows the finger; down meets a wall, because there is nothing
    // underneath to pull towards.
    setOffset(translation < 0 ? translation : translation * 0.1);
  };

  const onPointerUp = (): void => {
    if (dragStart.current === null || isLeaving.current) return;
    dragStart.current = null;
    if (offset < -70) leave();
    else setOffset(0);
  };

  return (
    <div
      className="fixed inset-0 z-[100] touch-none select-none overflow-hidden bg-[var(--sr-background)]"
      style={{
        transform: `translateY(${offset}px)`,
        transition: isStill ? "none" : "transform 420ms cubic-bezier(0.22, 1, 0.36, 1)",
      }}
      onPointerDown={onPointerDown}
      onPointerMove={onPointerMove}
      onPointerUp={onPointerUp}
      onPointerCancel={onPointerUp}
      onClick={leave}
      role="button"
      tabIndex={0}
      aria-label="SinRutina. Desliza hacia arriba o toca para entrar."
      onKeyDown={(event) => {
        if (event.key === "Enter" || event.key === " ") leave();
      }}
    >
      {/* Depth without decoration: two still pools of the person's own accent.
          Nothing here moves on its own. */}
      <div
        className="pointer-events-none absolute inset-0"
        style={{
          background:
            "radial-gradient(circle at 50% 36%, var(--sr-primary-a24), transparent 62%), radial-gradient(circle at 12% 92%, var(--sr-primary-a12), transparent 58%)",
        }}
      />

      <div className="relative flex h-full flex-col items-center justify-center px-8 text-center">
        <div
          className={cn("transition-all duration-500 ease-out")}
          style={{
            opacity: hasEntered ? 1 : 0,
            transform: hasEntered ? "scale(1)" : "scale(0.9)",
            transitionDuration: isStill ? "0ms" : "520ms",
          }}
        >
          <SRLogo height={124} />
        </div>

        <h1
          className="mt-7 text-[34px] font-semibold tracking-[-0.02em] text-[var(--sr-ink)] transition-opacity"
          style={{ opacity: hasEntered ? 1 : 0, transitionDuration: isStill ? "0ms" : "520ms" }}
        >
          SinRutina
        </h1>
        <p
          className="mt-2 text-[15px] text-[var(--sr-secondary-ink)] transition-opacity"
          style={{ opacity: hasEntered ? 0.9 : 0, transitionDuration: isStill ? "0ms" : "520ms" }}
        >
          Una cosa a la vez.
        </p>

        {/* The space is always reserved, so nothing below jumps when it appears. */}
        <div
          className="absolute bottom-14 flex h-11 flex-col items-center gap-1 text-[var(--sr-primary)] transition-opacity"
          style={{ opacity: showsHint ? 0.65 : 0, transitionDuration: isStill ? "0ms" : "320ms" }}
          aria-hidden="true"
        >
          <ChevronUp className="h-5 w-5" strokeWidth={2.5} />
          <span className="text-[13px] font-medium">Desliza para entrar</span>
        </div>
      </div>
    </div>
  );
}
