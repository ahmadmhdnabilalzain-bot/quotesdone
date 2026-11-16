import { assessQuote, validityOf, requirementsOf, type Line, type MissingItem, type Requirements } from '../../_shared/line_specs/assess.ts';
import type { Attr } from '../../_shared/line_specs/model.ts';
import { normText } from '../../_shared/line_specs/model.ts';
import { applyReading, readQuote } from '../../_shared/reasoned_matching.ts';
import { type ThinkDeps } from '../../_shared/think.ts';
import { statedPrice } from '../../_shared/stated_price.ts';
import { answerStands, vatOnTopOfLines } from '../../_shared/line_specs/vat.ts';
import { type Issue, type IssueCode, type Review, type SafeInquiry, TERM_CODES, type Working } from './types.ts';
import { heading, matchBoq, normUnit, priced } from './match.ts';
import { num, parseQty } from './working.ts';

// ---------------------------------------------------------------------------------------------
// The review.
// ---------------------------------------------------------------------------------------------
const cut = (s: unknown, n = 60) => { const t = normText(String(s ?? '')); return t.length > n ? t.slice(0, n - 1) + '…' : t; };
const fmt = (n: number) => (Number.isInteger(n) ? String(n) : n.toFixed(2));
const I = (code: IssueCode, kind: Issue['kind'], line_no: number | null, boq_line: number | null, attr: string | null, en: string, ar: string): Issue => ({ code, kind, line_no, boq_line, attr, en, ar });
const assessLines = (w: Working): Line[] => w.lines.map((l, i) => ({ line_no: i + 1, description: l.description, specification: l.specification ?? null, qty: l.qty, unit: l.unit, unit_price: l.unit_price, amount: l.amount, spec: l.spec ?? null, spec_source: l.spec_source ?? null }));

/**
 * What reasoning reads from the working quotation (decision points 29-30, _shared/reasoned_matching.ts readQuote),
 * written onto its lines' spec and its terms_spec as source 'reasoned', so the review asks exactly what the hold
 * gate will. Held (the model hold): the working is returned unread, and every detail is asked. No word reader.
 */
export async function readWorking(think: ThinkDeps, inq: SafeInquiry, w: Working, key: string): Promise<Working> {
  const lines = assessLines(w);
  const reading = await readQuote(think, { quoteId: key, category: inq.category, lines, requirements: requirementsOf(inq.spec),
    terms: { lead_time: w.lead_time, warranty: w.warranty, scope: w.scope, exclusions: w.exclusions, conditions: w.conditions, notes: w.notes, terms_spec: w.terms_spec } });
  if (!reading) return w;
  const ap = applyReading(lines, w.terms_spec, reading);
  return { ...w, terms_spec: ap.terms_spec, lines: w.lines.map((l, i) => ({ ...l, spec: ap.lines[i].spec ?? l.spec, spec_source: ap.lines[i].spec_source ?? l.spec_source })) };
}

/** desk: what the hold desk judges the exact specs with — the customer's requirements as the inquiry stores them, and the
 *  trade's knowledge-pack checklist. Given, rule 8 asks exactly what the desk asks (hold desk, finding a of 10 Nov 2026,
 *  re-run ea40c830); omitted (the quotation chat), the requirements are the ones the supplier inbox serves. */
export type DeskInputs = { requirements: Requirements; checklist?: Attr[] };
export function reviewQuotation(inq: SafeInquiry, w: Working, now: Date = new Date(), desk?: DeskInputs): Review {
  const issues: Issue[] = [];
  const boq = inq.boq_withheld ? [] : (inq.boq_rows || []).filter((r) => normText(String(r.description ?? '')));
  const lines = w.lines;

  // 1–2. The BOQ, line by line.
  const match = matchBoq(boq, lines);
  boq.forEach((b, i) => {
    const n = i + 1; const d = cut(b.description);
    if (w.boq_excluded[String(n)]) return;
    const j = match.get(i);
    const l = j == null ? null : lines[j];
    if (!l || !priced(l)) {
      issues.push(I('boq_line_not_priced', 'adjustment', l ? j! + 1 : null, n, null,
        `BOQ line ${n} (${d}) is not priced in your quotation. Add its price, or tell me it is excluded and why (for example: "BOQ line ${n} excluded — by others").`,
        `البند ${n} من جدول الكميات (${d}) غير مسعّر في عرضكم. يُرجى إضافة سعره، أو إفادتي بأنه مستثنى مع ذكر السبب (مثال: «البند ${n} مستثنى — يتولاه الغير»).`));
      return;
    }
    // A quantity and a unit are explained separately ("BOQ line 3 quantity — …" / "… unit — …"): an
    // explained quantity must not silence a unit that differs (TypeScript review, 15 Sep 2026).
    const bq = num(b.qty); const lq = parseQty(l.qty).n;
    if (!w.qty_explained[String(n)] && bq != null && lq != null && Math.abs(bq - lq) > Math.max(0.01, Math.abs(bq) * 0.01)) {
      issues.push(I('qty_mismatch', 'clarification', j! + 1, n, 'qty',
        `BOQ line ${n} (${d}): your line ${j! + 1} prices ${fmt(lq)} ${l.unit || ''}`.trimEnd() + ` but the BOQ asks for ${fmt(bq)} ${b.unit || ''}`.trimEnd() + `. Price the BOQ quantity, or tell me why yours differs (for example: "BOQ line ${n} quantity — measured on site").`,
        `البند ${n} من جدول الكميات (${d}): يسعّر بندكم ${j! + 1} كمية ${fmt(lq)} ${l.unit || ''}`.trimEnd() + `، في حين يطلب الجدول ${fmt(bq)} ${b.unit || ''}`.trimEnd() + `. يُرجى تسعير كمية الجدول، أو ذكر سبب الاختلاف (مثال: «البند ${n} الكمية — حسب القياس في الموقع»).`));
    }
    const bu = normUnit(b.unit), lu = normUnit(l.unit);
    if (!w.qty_explained[`${n}:unit`] && bu && lu && bu !== lu) {
      issues.push(I('unit_mismatch', 'clarification', j! + 1, n, 'unit',
        `BOQ line ${n} (${d}) is measured in ${b.unit}, your line ${j! + 1} in ${l.unit}. Re-state it in ${b.unit}, or explain the conversion.`,
        `البند ${n} من جدول الكميات (${d}) مقيس بوحدة ${b.unit}، بينما بندكم ${j! + 1} بوحدة ${l.unit}. يُرجى إعادة ذكره بوحدة ${b.unit}، أو توضيح طريقة التحويل.`));
    }
  });

  // 3. A line with a quantity and no price.
  lines.forEach((l, j) => {
    if (heading(l) || priced(l) || !l.qty) return;
    if ([...match.values()].includes(j)) return;   // already raised against its BOQ line
    // The supplier's explanation recorded on the hold desk ("included in line 2's price"), as rules 1, 2 and 4 take theirs.
    if (w.qty_explained[`line:${j + 1}`]) return;
    issues.push(I('line_unpriced', 'adjustment', j + 1, null, null,
      `Your line ${j + 1} (${cut(l.description)}) has a quantity but no price. Add its price.`,
      `بندكم ${j + 1} (${cut(l.description)}) ذُكرت كميته دون سعر. يُرجى إضافة سعره.`));
  });

  // 4b. What the model's reading asked him to confirm (an e-mailed quotation, 12 Nov 2026, review of #1981 D5): the same
  // plain questions the e-mail asked, and nothing is approved for submission until he has answered them in the thread.
  if (w.to_confirm?.length) {
    const en = 'Please confirm what we read from your quotation before it can be submitted:\n' + w.to_confirm.map((q, i) => `${i + 1}. ${q}`).join('\n')
      + '\nTell me if these are right, or give me the right figure, or attach a corrected file.';
    issues.push(I('reading_to_confirm', 'clarification', null, null, 'reading', en, en));   // suppliers are written in English only (ruling 1008)
  }

  // 5. Currency.
  if (w.foreign_currency) {
    issues.push(I('currency_not_aed', 'adjustment', null, null, 'currency',
      `Your quotation shows prices in ${w.foreign_currency}. Every price must be in UAE dirhams (AED): re-state them in AED, or reply "all prices in AED" if they already are.`,
      `يتضمّن عرضكم أسعارًا بعملة ${w.foreign_currency}، ويجب أن تكون الأسعار كافة بالدرهم الإماراتي. يُرجى إعادة ذكرها بالدرهم، أو كتابة «كل الأسعار بالدرهم» إن كانت كذلك.`));
  }

  // 6. The VAT basis. The price the customer compares is the price excluding VAT (vat.ts).
  const vatText = [w.notes, w.scope, w.conditions, w.exclusions, w.payment_terms].join('\n');
  const stated = w.vat_treatment && w.vat_treatment !== 'not_stated' ? w.vat_treatment : null;
  // The supplier's own lines are evidence of the VAT basis (line_specs/vat.ts, accountant 15 Nov 2026): a total that is exactly
  // their sum plus 5% has VAT in it. Single-option quotations only (options are totalled apiece).
  const singleOption = Object.keys(w.option_totals || {}).length < 2;
  const pricedLines = lines.filter((l) => !heading(l));
  const sum = pricedLines.reduce((s, l) => s + (Number(l.amount) || 0), 0);
  const counted = pricedLines.filter((l) => Number(l.amount) > 0).length;
  // Rulings 1207/1208: read after the supplier's stated discount; price_ex_vat is the after-discount, ex-VAT figure.
  const vat = statedPrice({ amount: w.amount, subtotal: w.subtotal, vat_amount: w.vat_amount, text: vatText, stated, price_ex_vat: w.price_ex_vat,
    gross_amount: w.gross_amount ?? null, discount_amount: w.discount_amount ?? null, discount_label: w.discount_label ?? null,
    lines_sum: singleOption ? sum : null, lines_count: counted, trn: w.trn, answered: answerStands(w.vat_answered, w.vat_treatment) });
  const vatIssue = vat.treatment === 'not_stated' || (vat.treatment === 'inclusive' && !vat.price_ex_vat);
  // ONE PLAIN QUESTION, THREE ANSWERS, AND THE ANSWER RELEASES THE QUOTE (sales_engineer, 13 Nov 2026, workflow audit build
  // item 10). The basis is asked with the supplier's own figure and the UAE rate, so "including 5% VAT" settles the ex-VAT
  // price on its own (line_specs/workflow.ts: total / 1.05) instead of asking a second question for a typed number; "before
  // VAT" and "not VAT-registered" make the figure itself the ex-VAT price. Silence and "includes VAT" with no rate ask it;
  // zero-rated and exempt are stated answers (line_specs/vat.ts) and are never asked.
  const shown = vat.total_as_stated ?? w.amount;
  // One number format in the one question (independent review of 15 Nov 2026: "AED 17957, and AED 18,854.85").
  const aedOf = (n: number) => `AED ${n.toLocaleString('en-US', { minimumFractionDigits: Number.isInteger(n) ? 0 : 2, maximumFractionDigits: 2 })}`;
  const fig = shown ? aedOf(Number(shown)) : 'your total';
  // The lines the total is measured against: less a stated discount, which the lines are before (stated_price.ts).
  const disc = Number(vat.discount_amount) > 0 && Number(vat.discount_amount) < sum ? Number(vat.discount_amount) : 0;
  const net = Math.round((sum - disc) * 100) / 100;
  // His figures contradict the basis he stated (the lines plus exactly 5% make his total): the same question, with the arithmetic.
  const why = vat.basis_conflict
    ? (disc ? `Your line amounts less the discount of ${aedOf(disc)} come to ${aedOf(net)}, and ${fig} is exactly that plus 5% VAT. ` : `Your line amounts add up to ${aedOf(net)}, and ${fig} is exactly that plus 5% VAT. `)
    : '';
  if (vatIssue) {
    issues.push(I('vat_basis', 'adjustment', null, null, 'vat',
      `${why}Is ${fig} including 5% VAT, or before VAT, or are you not VAT-registered? A business below the AED 375,000 registration threshold is not VAT-registered and needs no TRN.`,
      // the same question in Arabic (the hold desk renders body_ar only if a supplier's language were ever 'ar'; ruling 1008 keeps it 'en')
      `${vat.basis_conflict ? `مجموع مبالغ بنودكم${disc ? ' بعد الخصم' : ''} ${net.toLocaleString('en-US', { maximumFractionDigits: 2 })} درهم، و${fig} يساويه مضافًا إليه ضريبة 5% تمامًا. ` : ''}هل مبلغ ${fig} شامل ضريبة القيمة المضافة بنسبة 5%، أم قبل الضريبة، أم أنكم غير مسجّلين في الضريبة؟ والمنشأة التي تقل إيراداتها عن حد التسجيل البالغ 375,000 درهم غير مسجّلة ولا تحتاج إلى رقم ضريبي.`));
  }
  const exVat = vat.price_ex_vat;

  // 4. The lines add up to the total (a single-option quotation only; options are totalled apiece).
  // (sum and the priced lines are counted above, for the VAT basis.)
  // A stated discount explains the difference: the lines may add up to the price BEFORE the discount.
  const totals = [exVat, w.amount, w.subtotal, vat.gross_amount].filter((x): x is number => Number(x) > 0);
  // A difference of exactly 5% VAT while the VAT basis is being asked is that question, not a second one: answering it with
  // free text ("as per the quotation") released a VAT-inclusive total as the price before VAT (journey A, 15 Nov 2026).
  const vatIsTheGap = vatIssue && vatOnTopOfLines(net, vat.total_as_stated ?? w.amount, counted);
  if (sum > 0 && totals.length && !vatIsTheGap && !w.qty_explained?.total && singleOption && !totals.some((t) => Math.abs(t - sum) <= Math.max(1, t * 0.01))) {
    issues.push(I('total_mismatch', 'clarification', null, null, 'total',
      `Your line amounts add up to AED ${fmt(Math.round(sum * 100) / 100)}, but the quotation's total is AED ${fmt(totals[0])}. Correct the lines or the total, or tell me what the difference is (for example a discount).`,
      `مجموع مبالغ بنودكم ${fmt(Math.round(sum * 100) / 100)} درهم، في حين أن إجمالي العرض ${fmt(totals[0])} درهم. يُرجى تصحيح البنود أو الإجمالي، أو توضيح سبب الفرق (كخصم مثلًا).`));
  }

  // 7. Validity.
  // The hold desk's reader (assess.ts validityOf): a positive period or a date not yet passed, so release and desk agree.
  if (!validityOf(w.validity || '', now)) {
    issues.push(I('validity', 'adjustment', null, null, 'validity',
      'State how long your prices are valid, as a number of days or a date (for example: "validity 30 days").',
      'يُرجى ذكر مدة صلاحية أسعاركم بعدد الأيام أو بتاريخ محدد (مثال: «الصلاحية 30 يومًا»).'));
  }

  // 8. The exact-specs rules, exactly as the hold gate reads them.
  const a = assessQuote({ category: inq.category, lines: assessLines(w), requirements: desk ? desk.requirements : requirementsOf(inq.spec), checklist: desk?.checklist,
    terms: { lead_time: w.lead_time, warranty: w.warranty, scope: w.scope, exclusions: w.exclusions, conditions: w.conditions, notes: w.notes, terms_spec: w.terms_spec, price_ex_vat: exVat } });
  for (const m of a.missing) {
    if (m.attr === 'price_ex_vat' && vatIssue) continue;   // already asked, in the VAT basis's words
    issues.push(fromMissing(m));
  }
  return { approved: issues.length === 0, issues, price_ex_vat: exVat, boq_lines: boq.length, matched: match.size };
}

/** One missing detail the hold desk reports (assess.ts MissingItem), in the engineer's words. */
export function fromMissing(m: MissingItem): Issue {
  if (m.scope === 'line') {
    const d = cut(m.description);
    return I('spec', 'adjustment', m.line_no, null, m.attr,
      `Your line ${m.line_no} (${d}): state the exact ${m.label_en.toLowerCase()}${m.unit ? ` (${m.unit})` : ''} (for example: "line ${m.line_no} ${m.label_en.toLowerCase()}: …").`,
      `بندكم ${m.line_no} (${d}): يُرجى ذكر ${m.label_ar} بدقة${m.unit_ar || m.unit ? ` (${m.unit_ar || m.unit})` : ''} (مثال: «البند ${m.line_no} ${m.label_ar}: …»).`);
  }
  // assess.ts types MissingItem.attr as a plain string, so a term added there that nothing here knows
  // would otherwise reach the database as an invalid code. An unknown attribute is asked as a `spec`.
  const code: IssueCode = m.attr.startsWith('component:') ? 'component'
    : (TERM_CODES.has(m.attr as IssueCode) ? m.attr as IssueCode : 'spec');
  const ex: Record<string, [string, string]> = {
    delivery: [' (for example: "lead time 3 weeks")', ' (مثال: «مدة التسليم 3 أسابيع»)'],
    installation_included: [' (for example: "installation included, 5 working days on site" or "supply only")', ' (مثال: «التركيب مشمول، 5 أيام عمل في الموقع» أو «توريد فقط»)'],
    installation_detail: [' (for example: "installation 5 working days on site")', ' (مثال: «التركيب 5 أيام عمل في الموقع»)'],
    warranty_period: [' (for example: "warranty 2 years")', ' (مثال: «الضمان سنتان»)'],
    warranty_coverage: [' (for example: "warranty covers parts and labour")', ' (مثال: «الضمان يشمل القطع والعمالة»)'],
    price_ex_vat: [' (for example: "price excluding VAT 10,500")', ' (مثال: «السعر غير شامل الضريبة 10,500»)'],
  };
  const [en, ar] = ex[m.attr] ?? ['', ''];
  return I(code, 'adjustment', null, null, m.attr, `State: ${m.label_en}${en}.`, `يُرجى ذكر: ${m.label_ar}${ar}.`);
}

// Names the sibling modules of this folder import (the declarations above are unchanged).
export { assessLines, fmt };
