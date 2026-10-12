import { createClient } from 'jsr:@supabase/supabase-js@2';
import { envGatewayVision, b64Bytes } from '../_shared/read_every_attachment.ts';
import { clearerCopyAsk } from '../_shared/clearer_copy.ts';
import { readQuotationFile } from './quote_review_flow.ts';
import { sanitizeUpload, safeFilename, SAFE_UPLOAD, SAFE_DOCS, SAFE_SUPPLIER_PAPERS } from '../_shared/attachment.ts';
import { seedTerms } from '../_shared/anonymise.ts';
import { asLocale, SUPPLIER_LOCALE } from '../_shared/registered_locale.ts';
import { arDays } from '../_shared/ar_days.ts';
// MALWARE WATCH, 9 Sep 2026. Every file a supplier sends is hashed and looked up before it reaches
// storage; a hash VirusTotal already knows to be malicious is refused here rather than stored,
// forwarded and served back. See _shared/malware.ts for why the lookup blocks and the analysis does not.
import { sanitizeAndScan } from '../_shared/malware.ts';
import { observe } from '../_shared/observe.ts';
import { defaultDeps } from '../_shared/think.ts';
import { quoteTerms } from '../_shared/reasoned_suppliers.ts';
import { storedAt } from '../_shared/stored_at.ts';
import { CANONICAL_ORIGIN, siteReturnBase, siteCors } from '../_shared/site_origins.ts';
import { capabilityState, capabilityConfirm } from '../_shared/supplier_capability.ts';
import { servicesState, servicesResolve, servicesRewrite, servicesSaveRewrite, transcribeServiceNote, voiceEnabled } from '../_shared/supplier_services.ts';
import { boqWithArabic } from '../_shared/boq_arabic.ts';
import { boqReadings, liveReadingStore } from '../_shared/reasoned_documents.ts';
import { arabicOf, nativeArabic } from '../_shared/reasoned_governance.ts';
import { searchResult, SEARCH_COLUMNS, type LeadHit } from './search_result.ts';
import { mandatorySixMissing, sixInWords } from '../_shared/supplier_registration.ts';
import { clientIp, currentSupplierTermsVersion, supplierTermsRecord } from '../_shared/supplier_terms.ts';
import { proposeTradesFromDocs, modelReadText, type DocIn } from '../_shared/supplier_doc_trades.ts';
import { licenceModelPayload, licenceNameFromModel, licenceNeedsModel, readExpiry, readLicenceFields, readLicenceName, type LicenceFields } from '../_shared/document_expiry.ts';
// The sales engineer's hold desk (14 Sep 2026): exact specs per line, delivery, installation,
// warranty and the ex-VAT price, or the quote is held; options are separate quotations.
import { approve, fillIn, finishArabic, formSchema, gate, pdfDoc, supabaseRepo, type Render } from '../_shared/line_specs/workflow.ts';
import { requireInternal } from '../_shared/internal_auth.ts';
import { applyReading, readQuote } from '../_shared/reasoned_matching.ts';
import { assessQuote, requirementsOf } from '../_shared/line_specs/assess.ts';
import type { Attr } from '../_shared/line_specs/model.ts';
import { checklistAttrs, chooseChecklist, needsChecklist, reasonLineSpecs, unionOf, type Checklist, type ChecklistRow } from '../_shared/line_specs/reasoned_specs.ts';
import type { Line, MissingItem } from '../_shared/line_specs/assess.ts';
import type { Ctx } from '../_shared/line_specs/workflow.ts';
import { optionAmount, splitOptions } from '../_shared/line_specs/options.ts';
import { readVat } from '../_shared/line_specs/vat.ts';
import { findTrn } from '../_shared/identity_numbers.ts';
