import { readDelivery, readInstallation, readWarranty } from '../../_shared/line_specs/assess.ts';
import { readDiscount } from '../../_shared/stated_price.ts';
import { VAT_GAP_TOLERANCE } from '../../_shared/line_specs/vat.ts';
import { type BoqRow, type WLine, type Working } from './types.ts';
import { type Correction } from './reply.ts';
import { num } from './working.ts';
import { heading, matchBoq, priced, toks } from './match.ts';
import { assessLines } from './review.ts';

const r2 = (n: number) => Math.round(n * 100) / 100;
/** The working quotation with the supplier's stated details applied. Pure: returns a new object. `boq` is the job's BOQ, needed only to price a BOQ line. */
export function applyCorrections(w0: Working, cs: Correction[], boq: BoqRow[] = []): Working {
  const w: Working = structuredClone(w0);
  const log = (field: string, value: string, line: number | null = null) => w.corrections.push({ field, value, line });
  const drop = new Set<WLine>();
  for (const c of cs) {
    switch (c.field) {
      case 'boq_price': {
        const b = boq[c.boq_line - 1]; if (!b) break;
        const qty = num(b.qty);
        let unit_price = c.unit_price, amount = c.amount;
        if (unit_price == null && amount != null && qty) unit_price = r2(amount / qty);
        if (amount == null && unit_price != null && qty) amount = r2(unit_price * qty);
        if (amount == null && unit_price == null) break;
        // the quotation line already matched to this BOQ line is re-priced; otherwise the BOQ line
        // becomes a line of the quotation in the BOQ's own words, quantity and unit
        const j = matchBoq(boq, w.lines).get(c.boq_line - 1);
        if (j != null) { w.lines[j].unit_price = unit_price ?? w.lines[j].unit_price; w.lines[j].amount = amount ?? w.lines[j].amount; if (!w.lines[j].qty && qty != null) { w.lines[j].qty = String(qty); w.lines[j].unit = String(b.unit ?? ''); } }
        else w.lines.push({ description: String(b.description ?? ''), qty: qty == null ? '' : String(qty), unit: String(b.unit ?? ''), unit_price, amount });
        // a priced line is not an excluded one
        if (w.boq_excluded[String(c.boq_line)]) { delete w.boq_excluded[String(c.boq_line)]; w.exclusions = withoutExclusionNote(w.exclusions, c.boq_line); }
        // the total follows the lines the supplier priced; the VAT basis is asked separately
        retotal(w);
        log('boq_price', `${unit_price ?? ''}|${amount ?? ''}`, c.boq_line); break;
      }
      case 'line_price': {
        const l = w.lines[c.line_no - 1]; if (!l) break;
        const qty = num(l.qty);
        l.unit_price = c.unit_price ?? (c.amount != null && qty ? r2(c.amount / qty) : l.unit_price);
        l.amount = c.amount ?? (c.unit_price != null && qty ? r2(c.unit_price * qty) : l.amount);
        retotal(w); log('line_price', `${l.unit_price ?? ''}|${l.amount ?? ''}`, c.line_no); break;
      }
      case 'total': {
        w.amount = c.value; if (w.subtotal != null) w.subtotal = c.value; if (w.price_ex_vat != null) w.price_ex_vat = c.value; w.vat_amount = null;
        log('total', String(c.value)); break;
      }
      case 'total_explained': {
        w.qty_explained = { ...w.qty_explained, total: c.value };
        // Ruling 1207: a discount is a structured price field (gross, discount, final), not a condition. A difference
        // explained by something that is not a discount stays the supplier's words in the conditions.
        const d = readDiscount(c.value);
        const linesSum = w.lines.reduce((s, l) => s + (Number(l.amount) || 0), 0);
        if (d) {
          // The price before the discount is the larger of the lines and the stated total; the price after it is
          // that less the discount, and it becomes the quotation's ex-VAT figure (ruling 1208: never the gross).
          const gross = w.gross_amount ?? (Math.max(linesSum, Number(w.price_ex_vat ?? w.amount) || 0) || null);
          const disc = d.amount ?? (d.pct != null && gross != null ? r2(gross * d.pct / 100) : null);
          w.discount_label = d.label;
          if (gross != null && disc != null && disc < gross) {
            w.gross_amount = r2(gross); w.discount_amount = disc;
            const fin = r2(gross - disc);
            w.amount = fin; if (w.price_ex_vat != null) w.price_ex_vat = fin;
          }
        } else w.conditions = [w.conditions, c.value].filter(Boolean).join('; ').slice(0, 2000);
        log('total_explained', c.value); break;
      }
      case 'component': {
        w.terms_spec = { ...w.terms_spec, components: { ...(w.terms_spec.components ?? {}), [c.key]: { value: c.value, source: 'supplier_portal' } } };
        log(`component:${c.key}`, c.value); break;
      }
      case 'validity': w.validity = c.value; log('validity', c.value); break;
      case 'lead_time': w.lead_time = c.value; w.terms_spec = { ...w.terms_spec, delivery: { value: c.value, source: 'supplier_portal' } }; log('lead_time', c.value); break;
      case 'warranty': w.warranty = c.value; log('warranty', c.value); break;
      // HIS ANSWER STANDS IN THE CHAT EXACTLY AS AT THE HOLD DESK (ruling 1207; independent review of 15 Nov 2026). The chat
      // set the basis but never recorded that he had answered, so a total exactly his lines plus 5% re-raised the VAT question
      // after every "before VAT" (vat.ts basis_conflict) and nothing he said in the chat could clear it. Now a basis or an
      // ex-VAT figure he states here is his answer (w.vat_answered, as submit_review.ts withDeskAnswers records the desk's),
      // and "including VAT" drops an ex-VAT figure that IS the total (an earlier "before VAT" set it so), so the total less
      // the 5% is read again instead of the stale price surviving.
      case 'vat_treatment': {
        w.vat_treatment = c.value;
        if (c.value === 'inclusive') { if (w.price_ex_vat != null && w.amount != null && Math.abs(Number(w.price_ex_vat) - Number(w.amount)) <= VAT_GAP_TOLERANCE) w.price_ex_vat = null; }
        else w.price_ex_vat = c.value === 'not_registered' || c.value === 'exclusive' ? (w.amount ?? w.price_ex_vat) : w.price_ex_vat;
        w.vat_answered = c.value;
        log('vat_treatment', c.value); break;
      }
      case 'price_ex_vat': w.price_ex_vat = c.value; w.vat_treatment = 'confirmed_on_portal'; w.vat_answered = 'exclusive'; log('price_ex_vat', String(c.value)); break;
      case 'warranty_terms': {
        const prior = w.terms_spec.warranty ?? null; const read = readWarranty(w.warranty);
        const period = c.period ?? prior?.period ?? read.period ?? null;
        const coverage = c.coverage ?? prior?.coverage ?? read.coverage ?? '';
        w.warranty = [period, coverage].filter(Boolean).join(' — ');
        if (period) w.terms_spec = { ...w.terms_spec, warranty: { period, coverage, source: 'supplier_portal' } };
        log('warranty', w.warranty); break;
      }
      case 'installation': {
        const prior = w.terms_spec.installation ?? null;
        const detail = c.included === 'yes' ? (c.detail ?? prior?.detail ?? null) : null;
        w.terms_spec = { ...w.terms_spec, installation: { included: c.included, detail, source: 'supplier_portal' } };
        log('installation', c.included + (detail ? ' — ' + detail : '')); break;
      }
      case 'aed': w.foreign_currency = null; log('currency', 'AED'); break;
      case 'boq_excluded': {
        w.boq_excluded = { ...w.boq_excluded, [String(c.boq_line)]: c.value || 'excluded' };
        const note = `BOQ line ${c.boq_line} excluded${c.value ? ': ' + c.value : ''}`;
        w.exclusions = [w.exclusions, note].filter(Boolean).join('; ').slice(0, 2000);
        // EXCLUDED MEANS NOT IN THE PRICE (audit 21 Sep 2026, finding 4: the generated quotation read
        // "BOQ line 3 excluded — by others" while line 3 was priced AED 7,680 and counted in the total).
        // The supplier's word in the chat is the later one: the priced line leaves the quotation and the
        // total. It is dropped after every correction of this message, so a "line N" spec in the same
        // message still names the line the supplier saw.
        const j = boq.length ? matchBoq(boq, w.lines).get(c.boq_line - 1) : undefined;
        if (j != null && priced(w.lines[j])) drop.add(w.lines[j]);
        log('boq_excluded', c.value, c.boq_line); break;
      }
      case 'qty_explained': {
        const unit = c.what === 'unit';
        w.qty_explained = { ...w.qty_explained, [unit ? `${c.boq_line}:unit` : String(c.boq_line)]: c.value };
        w.conditions = [w.conditions, `BOQ line ${c.boq_line} ${unit ? 'unit' : 'quantity'}: ${c.value}`].filter(Boolean).join('; ').slice(0, 2000);
        log('qty_explained', c.value, c.boq_line); break;
      }
      case 'line_spec': {
        const l = w.lines[c.line_no - 1]; if (!l) break;
        l.spec = { ...(l.spec ?? {}), [c.attr]: c.value }; l.spec_source = { ...(l.spec_source ?? {}), [c.attr]: 'supplier_portal' };
        log(`line_spec:${c.attr}`, c.value, c.line_no); break;
      }
      // A Correction added to the union without a case here would otherwise be dropped in silence.
      default: { const _never: never = c; void _never; break; }
    }
  }
  if (drop.size) { w.lines = w.lines.filter((l) => !drop.has(l)); retotal(w); }
  return w;
}
/**
 * The total follows the priced lines. A VAT amount the file stated described the OLD total, so it is
 * cleared; the stated VAT treatment stands and the review asks the basis only if none was stated.
 */
function retotal(w: Working) {
  const sum = r2(w.lines.filter((l) => !heading(l)).reduce((s, l) => s + (Number(l.amount) || 0), 0));
  // A stated discount still applies to the new lines (ruling 1208: the price after the discount, never the gross).
  // The subtotal stays the BEFORE-discount figure, as the file wrote it; the final figures are after the discount.
  const disc = Number(w.discount_amount) > 0 && Number(w.discount_amount) < sum ? Number(w.discount_amount) : 0;
  if (disc) w.gross_amount = sum;
  const fin = r2(sum - disc);
  w.amount = fin; if (w.subtotal != null) w.subtotal = sum; if (w.price_ex_vat != null) w.price_ex_vat = fin;
  w.vat_amount = null;
}

const withoutExclusionNote = (s: string, n: number) => s.split(/;\s*/).filter((x) => !new RegExp(String.raw`^BOQ line ${n} excluded`).test(x)).join('; ');

// ---------------------------------------------------------------------------------------------
// A revised file keeps what the chat already settled (audit 21 Sep 2026, finding 12: after validity,
// installation and warranty were answered in the chat, a revised CSV re-opened all of them — 3 open
// points became 10). A new version replaces what the OLD FILE said; it does not un-say what the
// SUPPLIER said in the conversation. Rule: every term the new file states wins; every term it does
// not state keeps the conversation's answer; an exclusion stands only for a BOQ line the new file
// leaves unpriced; a line specification stated in the chat follows its line by description.
// ---------------------------------------------------------------------------------------------
export function carryOver(prev: Working | null, next: Working, boq: BoqRow[] = []): Working {
  if (!prev) return next;
  const w: Working = structuredClone(next);
  const log = (field: string, value: string, line: number | null = null) => w.corrections.push({ field: `carried:${field}`, value, line });
  for (const f of ['validity', 'lead_time', 'warranty', 'payment_terms'] as const) if (!w[f] && prev[f]) { w[f] = prev[f]; log(f, prev[f]); }
  const stated = (v: unknown) => v && v !== 'not_stated';
  if (!stated(w.vat_treatment) && stated(prev.vat_treatment)) {
    w.vat_treatment = prev.vat_treatment;
    if (prev.vat_treatment === 'exclusive' || prev.vat_treatment === 'not_registered') w.price_ex_vat = w.amount ?? w.price_ex_vat;
    else if (prev.price_ex_vat != null && prev.amount === w.amount) w.price_ex_vat = prev.price_ex_vat;
    // the basis carried is his answer, so his having answered it is carried with it (ruling 1207)
    if (prev.vat_answered) w.vat_answered = prev.vat_answered;
    log('vat_treatment', String(prev.vat_treatment));
  }
  if (w.foreign_currency && !prev.foreign_currency && prev.corrections.some((c) => c.field === 'currency')) { w.foreign_currency = null; log('currency', 'AED'); }
  // delivery / installation / warranty confirmed in the chat stay unless the new file states them
  const ts = { ...prev.terms_spec };
  if (readDelivery(w.lead_time)) delete ts.delivery;
  if (readWarranty(w.warranty).period) delete ts.warranty;
  if (readInstallation(assessLines(w), { scope: w.scope, conditions: w.conditions, notes: w.notes, exclusions: w.exclusions }).included) delete ts.installation;
  w.terms_spec = { ...ts, ...w.terms_spec };
  // exclusions and quantity reasons are about the job, not the file — unless the new file priced the line
  const match = matchBoq(boq, w.lines);
  for (const [n, why] of Object.entries(prev.boq_excluded || {})) {
    const j = match.get(Number(n) - 1);
    if (j != null && priced(w.lines[j])) continue;
    w.boq_excluded[n] = why; w.exclusions = [w.exclusions, `BOQ line ${n} excluded: ${why}`].filter(Boolean).join('; ').slice(0, 2000);
  }
  w.qty_explained = { ...(prev.qty_explained || {}), ...w.qty_explained };
  // a specification the supplier stated in the chat follows the line that says the same thing
  prev.lines.forEach((pl) => {
    const chat = Object.entries(pl.spec_source ?? {}).filter(([, s]) => s === 'supplier_portal').map(([k]) => k);
    if (!chat.length) return;
    const pt = new Set(toks(pl.description));
    const j = w.lines.findIndex((nl) => { const nt = toks(nl.description); return nt.length && nt.filter((t) => pt.has(t)).length / nt.length >= 0.5; });
    if (j < 0) return;
    const nl = w.lines[j];
    for (const k of chat) { if (!nl.spec?.[k]) { nl.spec = { ...(nl.spec ?? {}), [k]: pl.spec![k] }; nl.spec_source = { ...(nl.spec_source ?? {}), [k]: 'supplier_portal' }; log(`line_spec:${k}`, pl.spec![k], j + 1); } }
  });
  w.corrections = [...prev.corrections, ...w.corrections];
  return w;
}
