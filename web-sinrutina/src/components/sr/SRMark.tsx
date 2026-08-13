import { useAppearance } from "@/sr/AppearanceProvider";
import { PRESENCE_SCALE } from "@/sr/appearance";
import { cn } from "@/lib/utils";

/**
 * The visual presence of SinRutina: the winding path, and the dot ahead of it.
 *
 * This is the real logo, traced to vector so it can take the person's own accent
 * colour and stay sharp at any size. It is a shape, not a personality — no face,
 * no mascot, no character. The path winds, the dot waits further up, and that is
 * the whole vocabulary. There is no perpetual animation: continuous motion is
 * decoration, and decoration competes with the one thing on screen.
 */
export type PresenceState = "neutral" | "suggesting" | "waiting" | "focusing" | "completed";

const LABELS: Record<PresenceState, string> = {
  neutral: "SinRutina en calma",
  suggesting: "SinRutina tiene una sugerencia",
  waiting: "SinRutina esperando",
  focusing: "SinRutina acompañando el enfoque",
  completed: "Hecho",
};

const TINT_VAR: Record<PresenceState, string> = {
  neutral: "--sr-primary",
  suggesting: "--sr-primary",
  waiting: "--sr-lavender",
  focusing: "--sr-sky",
  completed: "--sr-mint",
};

/**
 * The outline of the path, traced from the logo artwork. Coordinates live in the
 * viewBox below; the shape is drawn once and tinted at use.
 */
const PATH =
  "M52 25C51.3 25.3 49.3 26.3 48 27C46.7 27.7 44.8 28.3 44 29C43.2 29.7 43.3 30.5 43 31C42.7 31.5 42.2 31.7 42 32C41.8 32.3 41.8 32.8 42 33C42.2 33.2 42.5 32.5 43 33C43.5 33.5 42.7 34.8 45 36C47.3 37.2 54.3 39 57 40C59.7 41 59.8 41.3 61 42C62.2 42.7 63.2 43.3 64 44C64.8 44.7 65.5 45.3 66 46C66.5 46.7 66.7 47.3 67 48C67.3 48.7 67.8 49.2 68 50C68.2 50.8 68.3 52 68 53C67.7 54 66.5 55.2 66 56C65.5 56.8 65.7 57.2 65 58C64.3 58.8 63.7 59.5 62 61C60.3 62.5 56.3 65.8 55 67C53.7 68.2 54.3 67.3 54 68C53.7 68.7 53.2 69.8 53 71C52.8 72.2 52.8 74 53 75C53.2 76 53.7 76.3 54 77C54.3 77.7 54 78 55 79C56 80 58.5 81.8 60 83C61.5 84.2 67.3 85.5 64 86C60.7 86.5 44.5 86.3 40 86C35.5 85.7 38.2 84.8 37 84C35.8 83.2 33.8 81.8 33 81C32.2 80.2 32.3 79.8 32 79C31.7 78.2 31.3 77 31 76C30.7 75 30 73.8 30 73C30 72.2 30.3 72 31 71C31.7 70 32.7 68.3 34 67C35.3 65.7 35.8 65 39 63C42.2 61 50.3 56.7 53 55C55.7 53.3 54.5 53.5 55 53C55.5 52.5 55.8 52.5 56 52C56.2 51.5 56 50.5 56 50C56 49.5 56.3 49.7 56 49C55.7 48.3 54.8 46.7 54 46C53.2 45.3 52.8 45.8 51 45C49.2 44.2 44.8 42 43 41C41.2 40 40.8 39.7 40 39C39.2 38.3 38.5 37.8 38 37C37.5 36.2 37.2 34.7 37 34C36.8 33.3 36.8 33.3 37 33C37.2 32.7 37.3 32.7 38 32C38.7 31.3 39.5 30 41 29C42.5 28 45.2 26.7 47 26C48.8 25.3 51.2 25.2 52 25C52.8 24.8 52.7 24.7 52 25Z";

/** The dot, sitting ahead of the path. Same place as in the artwork. */
const DOT = { cx: 50.4, cy: 18.3, r: 4.5 } as const;

/** Tight around the artwork, with a little air, so it centres inside the disc. */
const VIEW_BOX = "28 11 44 78";
const ASPECT = 44 / 78;

/**
 * The logo on its own, with no disc behind it — for the launch screen and
 * anywhere the mark is the only thing on screen.
 */
export function SRLogo({
  height,
  tint = "var(--sr-primary)",
  className,
}: {
  height: number;
  tint?: string;
  className?: string;
}) {
  return (
    <svg
      viewBox={VIEW_BOX}
      className={className}
      style={{ height, width: height * ASPECT }}
      role="img"
      aria-label="SinRutina"
    >
      <path d={PATH} fill={tint} style={{ transition: "fill var(--sr-duration-standard) ease" }} />
      <circle cx={DOT.cx} cy={DOT.cy} r={DOT.r} fill="var(--sr-blush)" />
    </svg>
  );
}

export function SRMark({
  state = "neutral",
  size = 46,
  respectsPresence = true,
  className,
}: {
  state?: PresenceState;
  size?: number;
  respectsPresence?: boolean;
  className?: string;
}) {
  const { profile } = useAppearance();
  const resolved = Math.round(size * (respectsPresence ? PRESENCE_SCALE[profile.presence] : 1));
  const tint = `var(${TINT_VAR[state]})`;
  const glyphHeight = resolved * 0.62;

  return (
    <span
      role="img"
      aria-label={LABELS[state]}
      className={cn("relative inline-grid shrink-0 place-items-center rounded-full", className)}
      style={{ width: resolved, height: resolved, backgroundColor: tint }}
    >
      {/* The disc is the tint at low opacity; drawn as an inner layer so the
          path and the dot keep full strength on top of it. */}
      <span
        className="absolute inset-0 rounded-full"
        style={{
          backgroundColor: "var(--sr-background)",
          opacity: state === "neutral" ? 0.9 : 0.85,
        }}
      />
      <svg
        viewBox={VIEW_BOX}
        className="relative"
        style={{ height: glyphHeight, width: glyphHeight * ASPECT }}
        aria-hidden="true"
      >
        <path d={PATH} fill={tint} style={{ transition: "fill var(--sr-duration-standard) ease" }} />
        <circle cx={DOT.cx} cy={DOT.cy} r={DOT.r} fill="var(--sr-blush)" />
      </svg>
    </span>
  );
}
