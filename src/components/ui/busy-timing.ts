// THE TWO NUMBERS, ALONE, WITH NO IMPORTS.
//
// They live apart from ui/busy.tsx for one measured reason. `busy.tsx` imports `Button`, which
// pulls in class-variance-authority and @radix-ui/react-slot. `RouteProgress` is mounted in the
// ROOT locale layout and needs only these two constants — importing them from `busy.tsx` put the
// whole Button/cva/Slot chain into the globally shared chunk (measured in the build output at
// 32,264 B raw / 12,744 B gzip, identified by `qd-hoverlit`, a string that exists only in
// button.tsx), and therefore into the first-load JS of the ~11 legal and content pages
// (about, blog, privacy, terms, services, …) that use no Button at all.
//
// The package has no `"sideEffects": false`, so the bundler is not free to prove that chain dead.
// A dependency-free module is.
//
// The rules these encode are in docs/CONVENTIONS_LOADING.md.

/** Show nothing below this — a 40ms round trip must not flash a spinner. */
export const SHOW_AFTER_MS = 150;
/** Once shown, hold at least this long — a 160ms round trip must not strobe. */
export const MIN_SHOW_MS = 300;
