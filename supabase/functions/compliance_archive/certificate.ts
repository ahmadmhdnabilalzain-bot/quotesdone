// certificate.ts - the signed-terms certificate's words, in the signer's language (pure; tested by
// certificate.test.ts). index.ts renders what this returns through pdf_native.
//
// Two defects found by the campaign registration walk of 21 Sep 2026 live here now:
//
// THE CERTIFICATE NAMED THE WRONG SIGNATORY. "Authorised signatory" printed fields.full_name, which for
// a supplier is the CONTACT (full_name || contact_name || signatory_name). A supplier who entered contact
// "ZZ DEMO Contact" and signatory "ZZ DEMO Signatory" received a legal record saying the contact signed.
//
// AN ARABIC-REGISTERED SUPPLIER RECEIVED AN ENGLISH-ONLY RECORD. The Supplier Agreement says the Arabic
// text prevails (clause 22), and every user-facing string is EN + AR; the certificate was English for
// everyone. It now follows the account's registered language (leads.locale / customers.locale), and an
// Arabic certificate is drawn right-to-left by pdf_native (lang 'ar').
export type CertFields = Record<string, string>;
export type Lang = 'en' | 'ar';

export function certFields(rec: Record<string, unknown>, kind: string): Pick<CertFields, 'full_name' | 'signatory'> {
  const s = (v: unknown) => (v == null ? '' : String(v)).trim();
  const full = s(rec.full_name) || s(rec.contact_name) || s(rec.signatory_name);
  return { full_name: full, signatory: kind === 'supplier' ? (s(rec.signatory_name) || s(rec.contact_name) || full) : '' };
}

// THE CERTIFICATE CERTIFIES THE ACCEPTANCE ROW, NOT TODAY'S SECRETS (sales_engineer, 24 Sep 2026).
// Measured on lead 126512 (ZZ DEMO, v13): leads.accepted_terms_sha256 = 0d99185f... (SHA-256 of the
// exported v13 EN+AR text, _shared/supplier_terms.ts), while the certificate printed the SHA-256 of
// app_secrets supplier_terms_html = fd487a4f... - two different fingerprints for one acceptance. The
// version label also came from the live secret, so a supplier who accepted v12 and is re-certified
// after v14 would be printed as having accepted v14. The stored version, hash and user agent win;
// the live values are used only where the row has none (older acceptances).
export function supplierEvidence(rec: Record<string, unknown>, liveLabel: string, liveHash: string): { terms_label: string; hash: string; ua: string } {
  const s = (v: unknown) => (v == null ? '' : String(v)).trim();
  const n = (s(rec.accepted_terms_version).match(/^v?(\d+)$/i) || [])[1];
  return {
    terms_label: n ? `Supplier Agreement — Version ${n}` : liveLabel,
    hash: s(rec.accepted_terms_sha256) || liveHash,
    ua: s(rec.accepted_terms_user_agent),
  };
}

export const certLang = (rec: Record<string, unknown>): Lang => (String(rec.locale || '').toLowerCase() === 'ar' ? 'ar' : 'en');

const L = {
  en: {
    title: 'Certificate of Acceptance — Terms & Conditions',
    full: 'Full name', company: 'Company', signatory: 'Authorised signatory', dob: 'Date of birth', mobile: 'Mobile', email: 'Email',
    type: 'Account type', supplier: 'Supplier', customer: 'Customer', terms: 'Terms accepted', utc: 'Accepted at (UTC)', local: 'Accepted at (local)',
    ip: 'IP address', ua: 'Browser (user agent)', notRecorded: 'Not recorded', method: 'Method', methodV: 'Click-to-accept checkbox at registration', hash: 'Document integrity (SHA-256)',
    field: 'Field', detail: 'Detail', hTerms: 'Terms accepted', hPen: 'Penalties for breach',
    docS: 'QuotesDone Supplier Agreement &amp; Platform Terms', docC: 'QuotesDone Customer Terms &amp; Conditions',
    intro: (doc: string) => `This certificate records the electronic acceptance of the ${doc} by the party identified below. Acceptance was given by ticking the &quot;I accept&quot; box during registration on the QuotesDone platform, which under the laws of the United Arab Emirates (including the Electronic Transactions and Trust Services Law) constitutes a valid and binding electronic acceptance.`,
    accepted: (doc: string, label: string, url: string) => `By registering, the party accepted the ${doc} (${label}), published in full at ${url}. The key binding obligations accepted include:`,
    clausesS: ['No-circumvention: no off-platform dealing with a customer introduced through the Platform for 24 months.', 'Confidentiality: no copying, reuse or disclosure of platform leads, customer data, pricing or anonymised scopes.', 'No replication or competing use of the Platform&#39;s software, matching logic or outputs.'],
    clausesC: ['No use of the Platform to build, benchmark or assist a competing product or service.', 'No scraping, copying or reuse of supplier data, pricing or platform content.', 'No reverse-engineering or replication of the Platform&#39;s software, matching logic or outputs.'],
    penS: 'Breach of the no-circumvention obligation entitles QuotesDone to agreed compensation of AED 20,000 per incident, or five (5) times the fee that would otherwise have been payable, whichever is higher, which includes the fee on that job. Sharing contact details during anonymised stages: agreed compensation of AED 10,000 per incident, never on top of the no-circumvention sum. Breach of the confidentiality or data-reuse obligation: agreed compensation of AED 25,000 per incident. A fake, duplicate or impersonating account, or a fraudulent quotation: agreed compensation of AED 20,000 per account or incident, and closure of the accounts concerned. A non-response refund: the exact amount refunded, the payment processor fee QuotesDone could not recover, an administrative fee of AED 500 and simple interest at 12% per annum, and, if unpaid, the official fees of recovering it. Each sum is agreed in advance as a genuine pre-estimate of loss under the Civil Transactions Law and is charged once for any one act; QuotesDone may also seek an order stopping a continuing breach.',
    penC: 'For a business customer, a breach of the above obligations entitles QuotesDone to agreed compensation of AED 20,000 per incident, immediate suspension or termination of the account, and an order stopping a continuing breach; these amounts are agreed as a genuine pre-estimate of loss under the Civil Transactions Law. For a consumer, QuotesDone may suspend or terminate the account and recover its actual, proven loss, and every statutory consumer right prevails.',
    hashNote: 'The SHA-256 value above is a cryptographic fingerprint of the exact Terms text that was accepted. Any later change to that text produces a different fingerprint, allowing the accepted version to be independently verified.',
    system: 'This is a system-generated record issued by QuotesDone Technologies and is valid without a handwritten signature.',
    label: (kind: string, label: string) => label,
    local_: (iso: string) => { try { return new Date(iso).toLocaleString('en-GB', { timeZone: 'Asia/Dubai', day: '2-digit', month: 'short', year: 'numeric', hour: '2-digit', minute: '2-digit' }) + ' (GST)'; } catch { return iso; } },
  },
  ar: {
    title: 'شهادة قبول — الشروط والأحكام',
    full: 'الاسم الكامل', company: 'الشركة', signatory: 'المفوّض بالتوقيع', dob: 'تاريخ الميلاد', mobile: 'الجوال', email: 'البريد الإلكتروني',
    type: 'نوع الحساب', supplier: 'مورّد', customer: 'عميل', terms: 'الشروط المقبولة', utc: 'وقت القبول (UTC)', local: 'وقت القبول (بتوقيت الإمارات)',
    ip: 'عنوان IP', ua: 'المتصفح (وكيل المستخدم)', notRecorded: 'غير مسجَّل', method: 'طريقة القبول', methodV: 'وضع علامة في خانة «أوافق» عند التسجيل', hash: 'بصمة المستند (SHA-256)',
    field: 'الحقل', detail: 'التفاصيل', hTerms: 'الشروط المقبولة', hPen: 'الجزاءات عند الإخلال',
    docS: 'اتفاقية المورّد وشروط منصة QuotesDone', docC: 'الشروط والأحكام للعملاء لدى QuotesDone',
    intro: (doc: string) => `تُثبت هذه الشهادة القبول الإلكتروني ${doc.startsWith("ال") ? "لل" + doc.slice(2) : "ل" + doc} من قِبَل الطرف المبيَّن أدناه. تمّ القبول بوضع علامة في خانة «أوافق» أثناء التسجيل على منصة QuotesDone، وهو قبول إلكتروني صحيح وملزم بموجب قوانين دولة الإمارات العربية المتحدة، بما فيها قانون المعاملات الإلكترونية وخدمات الثقة.`,
    accepted: (doc: string, label: string, url: string) => `بالتسجيل، قبِل الطرف ${doc} (${label})، المنشورة كاملةً على ${url}. ومن أهم الالتزامات الملزمة المقبولة:`,
    clausesS: ['عدم الالتفاف: عدم التعامل خارج المنصة مع أي عميل تمّ التعريف به عبر المنصة لمدة 24 شهرًا.', 'السرية: عدم نسخ فرص المنصة أو بيانات العملاء أو الأسعار أو نطاقات العمل المجهّلة، أو إعادة استخدامها أو إفشائها.', 'عدم استنساخ برمجيات المنصة أو منطق المطابقة أو مخرجاتها، أو استخدامها استخدامًا منافسًا.'],
    clausesC: ['عدم استخدام المنصة لبناء منتج أو خدمة منافسة أو قياسها أو المساعدة فيها.', 'عدم كشط بيانات المورّدين أو أسعارهم أو محتوى المنصة أو نسخها أو إعادة استخدامها.', 'عدم إجراء هندسة عكسية لبرمجيات المنصة أو منطق المطابقة أو مخرجاتها أو استنساخها.'],
    penS: 'يحقّ لـ QuotesDone عند الإخلال بالتزام عدم الالتفاف تعويض اتفاقي قدره 20,000 درهم إماراتي عن كل واقعة، أو خمسة (5) أضعاف الرسوم التي كانت ستُستحق، أيهما أعلى، ويشمل ذلك رسوم العمل ذاته. وعن مشاركة بيانات الاتصال خلال المراحل مجهولة الهوية: تعويض اتفاقي قدره 10,000 درهم إماراتي عن كل واقعة، ولا يُضاف إلى مبلغ عدم الالتفاف. وعند الإخلال بالتزام السرية أو إعادة استخدام البيانات: تعويض اتفاقي قدره 25,000 درهم إماراتي عن كل واقعة. وعن الحساب الوهمي أو المكرر أو المنتحل، أو عرض السعر الاحتيالي: تعويض اتفاقي قدره 20,000 درهم إماراتي عن كل حساب أو واقعة، وإغلاق الحسابات المعنية. وعن الاسترداد بسبب عدم الاستجابة: المبلغ المستردّ بالضبط، ورسوم مزوّد خدمة الدفع التي لم تتمكن QuotesDone من استردادها، ورسم إداري قدره 500 درهم إماراتي، وفائدة بسيطة بنسبة 12% سنويًا، والرسوم الرسمية لتحصيله إن لم يُسدَّد. وكل مبلغ منها متفق عليه مقدمًا بوصفه تقديرًا حقيقيًا مسبقًا للضرر وفق قانون المعاملات المدنية، ويُستحق مرة واحدة عن الفعل الواحد؛ ويجوز لـ QuotesDone كذلك طلب أمر بوقف الإخلال المستمر.',
    penC: 'إذا كان العميل تجاريًا، يحقّ لـ QuotesDone عند أي إخلال بالالتزامات أعلاه تعويض اتفاقي قدره 20,000 درهم إماراتي عن كل واقعة، والإيقاف الفوري للحساب أو إنهاؤه، وطلب أمر بوقف الإخلال المستمر؛ وهذه المبالغ متفق عليها بوصفها تقديرًا حقيقيًا مسبقًا للضرر وفق قانون المعاملات المدنية. وإذا كان العميل مستهلكًا، يجوز لـ QuotesDone إيقاف الحساب أو إنهاؤه واسترداد ضررها الفعلي المثبت، وتسود جميع حقوق المستهلك المقررة قانونًا.',
    hashNote: 'قيمة SHA-256 أعلاه بصمة تشفيرية للنص الدقيق للشروط التي تمّ قبولها. أي تغيير لاحق على ذلك النص ينتج بصمة مختلفة، ما يتيح التحقق المستقل من النسخة المقبولة.',
    system: 'هذا سجلّ صادر آليًا عن QuotesDone Technologies، وهو صالح دون توقيع بخط اليد.',
    // The stored label is English ("Supplier Agreement — Version 12"); the version number is what it carries.
    label: (kind: string, label: string) => { const v = (String(label).match(/(\d+)\s*$/) || [])[1]; return v ? `${kind === 'supplier' ? 'اتفاقية المورّد' : 'الشروط والأحكام للعملاء'} — الإصدار ${v}` : label; },
    local_: (iso: string) => { try { return new Date(iso).toLocaleString('ar-AE-u-nu-latn', { timeZone: 'Asia/Dubai', day: '2-digit', month: 'long', year: 'numeric', hour: '2-digit', minute: '2-digit' }) + ' (بتوقيت الخليج)'; } catch { return iso; } },
  },
};

export function identityRows(fields: CertFields, kind: string, lang: Lang = 'en'): [string, string][] {
  const t = L[lang];
  const rows: [string, string][] = [[t.full, fields.full_name]];
  if (kind === 'supplier') rows.push([t.company, fields.company], [t.signatory, fields.signatory || fields.full_name]);
  return rows;
}

const esc = (s: unknown) => String(s == null ? '' : s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');

/** The certificate's title and body, in `lang`. Values stay exactly as recorded. */
export function certificate(fields: CertFields, kind: string, hash: string, termsUrl: string, lang: Lang = 'en'): { title: string; body_html: string; lang: Lang } {
  const t = L[lang];
  const rows = identityRows(fields, kind, lang);
  if (fields.dob) rows.push([t.dob, fields.dob]);
  rows.push([t.mobile, fields.phone], [t.email, fields.email], [t.type, kind === 'supplier' ? t.supplier : t.customer],
    [t.terms, t.label(kind, fields.terms_label)], [t.utc, fields.accepted_utc], [t.local, t.local_(fields.accepted_iso)],
    [t.ip, fields.ip || t.notRecorded]);
  // Only the supplier acceptance records a user agent; a customer certificate keeps its former rows.
  if (kind === 'supplier') rows.push([t.ua, fields.ua || t.notRecorded]);
  rows.push([t.method, t.methodV], [t.hash, hash]);
  const doc = kind === 'supplier' ? t.docS : t.docC;
  const trs = rows.map(([k, v]) => `<tr><td>${esc(k)}</td><td>${esc(v)}</td></tr>`).join('');
  const clauses = '<ul>' + (kind === 'supplier' ? t.clausesS : t.clausesC).map((c) => `<li>${c}</li>`).join('') + '</ul>';
  const url = lang === 'ar' ? termsUrl.replace('quotesdone.com/', 'quotesdone.com/ar/') : termsUrl;
  const body_html = `<p>${t.intro(doc)}</p><table><thead><tr><th>${t.field}</th><th>${t.detail}</th></tr></thead><tbody>${trs}</tbody></table>`
    + `<h3>${t.hTerms}</h3><p>${t.accepted(doc, esc(t.label(kind, fields.terms_label)), url)}</p>${clauses}`
    + `<h3>${t.hPen}</h3><p>${kind === 'supplier' ? t.penS : t.penC}</p><p>${t.hashNote}</p><p>${t.system}</p>`;
  return { title: t.title, body_html, lang };
}
