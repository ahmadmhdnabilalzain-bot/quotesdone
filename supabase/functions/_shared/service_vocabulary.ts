// THE SERVICE VOCABULARY, AND WHAT A TEXT NAMES IN IT (22 Sep 2026, agent: sales_engineer).
//
// One owner for two questions that must never be answered differently:
//   serviceVocab(admin)        — the active taxonomy_trade_service rows with their aliases.
//   inquiryServiceKeys(...)    — the '<trade>.<code>' keys an INQUIRY names, read with the same
//                                exact-alias matcher the supplier's own sentence is read with
//                                (_shared/service_rewrite.ts servicesFromText).
//
// WHY IT IS ONE FILE. The founder calls services "our cross matching main source" and his rule is
// "either exact match or no match" (15 Sep 2026). That rule only holds if the inquiry side and the
// supplier side read the SAME vocabulary with the SAME matcher: a second reader, however small, is
// a second answer about who receives a request. supplier_services.ts (the Services tab) imports
// serviceVocab from here rather than keeping its own copy of the select.
import { jsonText, servicesFromText, type ServiceTerm } from './service_rewrite.ts';

// deno-lint-ignore no-explicit-any
type Admin = any;

/** The alias vocabulary the rewriter matches with: every active service and the phrases that name it. */
export async function serviceVocab(admin: Admin): Promise<ServiceTerm[]> {
  const { data, error } = await admin.from('taxonomy_trade_service')
    .select('trade_code,code,label_en,label_ar,aliases,install_work').eq('active', true).order('trade_code').order('sort');
  return error ? [] : (data || []);
}

/**
 * The service keys an inquiry asks for: its brief and every string in its BOQ, read exactly.
 * An empty answer is a real answer — the brief names no service this taxonomy knows — and callers
 * pass it to fn_match_capability as an empty p_services, which leaves every candidate through and
 * falls back to trade-level matching rather than dropping the inquiry.
 */
export function serviceKeysOf(brief: string, boq: unknown, vocab: ServiceTerm[]): string[] {
  const text = [String(brief || ''), jsonText(boq).join('\n')].filter((s) => s.trim()).join('\n');
  return text ? servicesFromText(text, vocab) : [];
}
