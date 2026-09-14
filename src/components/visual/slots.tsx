// Mount points for the 3D/motion layer (branch web-audit-visual-3d). The visual agent replaces this
// file's contents with lazy-loaded scenes that paint after first paint, keep a static poster and
// respect prefers-reduced-motion. Until then every slot renders nothing, so the pages build and the
// server-rendered text stays the LCP element.
type SlotProps = { className?: string; locale?: string };

export function HeroScene(_p: SlotProps) { return null; }
export function EmiratesMap(_p: SlotProps) { return null; }
export function DrawingScan(_p: SlotProps) { return null; }
export function CompareLevelling(_p: SlotProps) { return null; }
export function AnonymityFlow(_p: SlotProps) { return null; }
