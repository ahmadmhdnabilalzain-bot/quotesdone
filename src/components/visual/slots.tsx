// Mount points for the 3D/motion layer (branch web-audit-visual-3d). Integration takes the visual
// agent's version of this file; this no-op copy only keeps this branch compiling. Each slot takes
// {locale} and fills its parent, so the parent decides the size (see Hero, EngineStrip, /supplier,
// /how-it-works). Until then every slot renders nothing and the server-rendered text stays the LCP.
type SlotProps = { locale?: string };

export function HeroScene(_p: SlotProps) { return null; }
export function EmiratesMap(_p: SlotProps) { return null; }
export function DrawingScan(_p: SlotProps) { return null; }
export function CompareLevelling(_p: SlotProps) { return null; }
export function AnonymityFlow(_p: SlotProps) { return null; }
