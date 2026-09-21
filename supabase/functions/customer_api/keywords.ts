// The brief-text keywords a new inquiry carries (inquiries.keywords) and the emirate read from its
// text. Lifted out of index.ts on 21 Sep 2026 so the blocker below has a test that runs without the
// server.
//
// 14 Sep 2026: the category comes from _shared/trade_classify (the intake's own reading). This map
// scored raw substrings one point each, so "ground floor fire alarm" tied flooring, security and
// safety and went to flooring. KW now only fills inquiries.keywords, which the sales engineer reads
// as brief text when an inquiry carries no trades (fn_norm_trades, exact aliases); since 15 Sep 2026
// no keyword matcher consumes it.
//
// 21 Sep 2026 (customer audit, BLOCKER): detectCat knows every category_specs slug — electrical,
// plumbing, hvac, mep… — and this map knows sixteen. An electrical request (DB board, cables,
// sockets) resolved to 'electrical', KW['electrical'] was undefined, and create_inquiry answered
// 500 "Cannot read properties of undefined (reading 'filter')" on every send, reproduced 3x by the
// auditor. A category this map has no words for contributes no keywords; the category is still
// recorded and the request still goes out.
import { detectCat } from '../_shared/trade_classify.ts';

export const KW: Record<string, string[]> = {
  flooring: ['floor', 'flooring', 'spc', 'vinyl', 'lvt', 'parquet', 'laminate', 'epoxy', 'tile', 'tiles', 'marble', 'granite', 'carpet'], glass: ['glass', 'glazing', 'mirror', 'shower enclosure', 'partition', 'facade', 'curtain wall', 'window'], aluminium: ['aluminium', 'aluminum', 'pergola', 'cladding', 'composite panel', 'window frame'], steel: ['steel', 'metal', 'fabrication', 'welding', 'staircase', 'railing', 'gate', 'structure'], acrylic: ['acrylic', 'plexiglass', 'perspex', 'display stand'], carpentry: ['carpentry', 'wood', 'joinery', 'wardrobe', 'cabinet', 'kitchen', 'furniture', 'door'], gypsum: ['gypsum', 'false ceiling', 'drywall', 'partition wall', 'ceiling'], signage: ['sign', 'signage', '3d letters', 'lightbox', 'led sign', 'billboard', 'sticker', 'branding'], wallpaper: ['wallpaper', 'wall covering'], upholstery: ['upholstery', 'sofa', 'curtain', 'blinds', 'cushion', 'reupholster'], fitout: ['fitout', 'fit-out', 'fit out', 'interior', 'renovation', 'refurbish', 'turnkey', 'decoration'], painting: ['paint', 'painting', 'varnish', 'coating'], landscaping: ['landscaping', 'garden', 'grass', 'artificial grass', 'irrigation', 'swimming pool', 'pool'], scaffolding: ['scaffolding', 'scaffold', 'formwork'], security: ['cctv', 'camera', 'access control', 'intercom', 'alarm', 'security system', 'gate barrier'], safety: ['safety', 'ppe', 'fire extinguisher', 'fire alarm', 'first aid', 'helmet'],
};
const EMIRATES = ['Dubai', 'Abu Dhabi', 'Sharjah', 'Ajman', 'Ras Al Khaimah', 'Umm Al Quwain', 'Fujairah'];

export function detect(text: string): { category: string | null; emirate: string | null; keywords: string[] } {
  const t = ' ' + String(text || '').toLowerCase() + ' ';
  const best = detectCat(text);
  let em: string | null = null;
  for (const e of EMIRATES) { if (t.includes(e.toLowerCase())) { em = e; break; } }
  if (!em && t.includes('abudhabi')) em = 'Abu Dhabi'; if (!em && / rak /.test(t)) em = 'Ras Al Khaimah';
  return { category: best, emirate: em, keywords: best ? (KW[best] || []).filter((k) => t.includes(k)) : [] };
}
