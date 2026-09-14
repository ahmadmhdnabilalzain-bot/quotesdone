// classify — the deterministic trade, emirate and urgency reading of a customer's words. No model.
//
// Moved out of index.ts on 14 Sep 2026 so it can be tested. The case that forced it: the founder
// typed "I need Generators work (generators)" in the portal at 08:42 and 08:43 UTC. `generators` is a
// category_specs slug, but this map had no entry for it, so detectCat returned null, the kb router
// found only a weak fragment ("Industrial Equipment Suppliers", score 2) and asked the customer to
// choose between that and "something else". The category fell to 'general', readiness sat at 10,
// and no inquiry was ever created (inquiry_intake e94c7678 and b08d3296). A slug that exists in
// category_specs and has no words here cannot be reached by an English request under the model hold.
export const KW: Record<string, string[]> = {
  flooring: ['floor', 'flooring', 'spc', 'vinyl', 'lvt', 'epoxy', 'parquet', 'laminate', 'tiles floor', 'marble floor', 'carpet'],
  glass: ['glass', 'glazing', 'shower enclosure', 'mirror', 'partition glass', 'facade', 'curtain wall', 'railing glass'],
  aluminium: ['aluminium', 'aluminum', 'window frame', 'sliding window', 'thermal break'],
  steel: ['steel', 'metal fabric', 'stainless', 'gate steel', 'staircase steel', 'canopy'],
  gypsum: ['gypsum', 'ceiling', 'false ceiling', 'partition wall', 'drywall', 'plasterboard'],
  painting: ['paint', 'painting', 'painters', 'repaint', 'wall paint', 'texture paint'],
  carpentry: ['carpentry', 'joinery', 'wardrobe', 'kitchen cabinet', 'mdf', 'woodwork', 'wooden door'],
  fitout: ['fit out', 'fit-out', 'fitout', 'interior', 'renovation', 'refurbish', 'office fitout', 'shop fitout'],
  landscaping: ['landscap', 'garden', 'gardening', 'turf', 'grass', 'irrigation', 'plants', 'softscape', 'hardscape'],
  electrical: ['electric', 'wiring', 'db board', 'lighting install', 'electrician', 'power point', 'dewa connection'],
  plumbing: ['plumb', 'plumbing', 'water leak', 'drainage', 'sanitary', 'pipe', 'water tank', 'geyser'],
  hvac: ['air condition', 'hvac', 'chiller', 'ducting', 'split unit', 'fahu', 'ahu', 'cooling'],
  cleaning: ['clean', 'cleaning', 'deep clean', 'housekeeping', 'facade cleaning', 'sofa cleaning'],
  waterproofing: ['waterproof', 'water proofing', 'membrane', 'roof leak', 'bathroom leak'],
  tiling: ['tiling', 'tiler', 'wall tiles', 'ceramic tiles', 'grouting'],
  masonry: ['masonry', 'block work', 'blockwork', 'plaster', 'concrete', 'screed'],
  mep: ['mep', 'mechanical electrical plumbing'],
  signage: ['signage', 'sign board', '3d letters', 'acrylic sign', 'led sign', 'billboard'],
  security: ['cctv', 'access control', 'security system', 'alarm', 'intercom', 'gate barrier'],
  scaffolding: ['scaffold', 'scaffolding', 'access platform'],
  upholstery: ['upholstery', 'curtain', 'curtains', 'sofa reupholster', 'blinds'],
  wallpaper: ['wallpaper', 'wall covering', 'wall mural'],
  pest: ['pest', 'pest control', 'termite', 'cockroach', 'fumigation'],
  movers: ['moving', 'movers', 'relocation', 'shifting', 'packing'],
  'custom-furniture': ['custom furniture', 'bespoke furniture', 'reception desk', 'display counter'],
  acrylic: ['acrylic', 'perspex', 'plexiglass'],
  tents: ['tent', 'shade', 'car park shade', 'pergola', 'gazebo'],
  safety: ['fire fighting', 'fire alarm', 'sprinkler', 'fire extinguisher', 'civil defence'],
  roofing: ['roof', 'roofing', 'gi sheet', 'roof tiles', 'roof leak'],
  solar: ['solar', 'pv panel', 'photovoltaic', 'solar panel'],
  'smart-home': ['smart home', 'home automation', 'automation', 'smart lighting', 'knx'],
  'swimming-pools': ['swimming pool', 'pool', 'jacuzzi'],
  'interior-design': ['interior design', 'designer', 'mood board', '3d design'],
  elevators: ['elevator', 'lift', 'escalator'],
  // 14 Sep 2026 — see the header. Arabic included: مولد / مولدات is how a customer writes it.
  generators: ['generator', 'genset', 'gen set', 'gen-set', 'backup power', 'standby power', 'مولد', 'مولّد', 'مولدات'],
};
export const EMIRATES = ['Dubai', 'Abu Dhabi', 'Sharjah', 'Ajman', 'Ras Al Khaimah', 'Fujairah', 'Umm Al Quwain', 'Al Ain'];
export function detectCat(text: string): string | null { const t = ' ' + String(text || '').toLowerCase() + ' '; let best: string | null = null; let bestN = 0; for (const [cat, ks] of Object.entries(KW)) { let n = 0; for (const k of ks) if (t.includes(k)) n++; if (n > bestN) { bestN = n; best = cat; } } return best; }
export function detectTrades(text: string): string[] { const t = ' ' + String(text || '').toLowerCase() + ' '; const hits: string[] = []; for (const [cat, ks] of Object.entries(KW)) { if (ks.some((k) => t.includes(k))) hits.push(cat); } return hits; }
export function detectEmirate(text: string): string | null { const t = String(text || '').toLowerCase(); for (const e of EMIRATES) if (t.includes(e.toLowerCase())) return e; if (t.includes('rak')) return 'Ras Al Khaimah'; return null; }
export function detectUrgency(text: string): string { const t = ' ' + String(text || '').toLowerCase() + ' '; if (/(emergency|urgent|asap|immediately|today|right now|flooding|burst|no power|sparking|gas leak|leaking badly)/.test(t)) return 'urgent'; return 'normal'; }
export function isArabic(text: string): boolean { return /[؀-ۿ]/.test(String(text || '')); }
