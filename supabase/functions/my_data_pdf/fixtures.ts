// ZZ DEMO exports in the shape pdpl_request_me('export') returns (the shape of
// scripts/sql/a_copy_of_a_persons_data_holds_their_own_records_and_nobody_elses.sql), for the tests and the sample
// renders. Every person here is invented; addresses are @example.invalid.

export const SUPPLIER_EXPORT = {
  email: 'zz-demo-supplier@example.invalid',
  generated_at: '2026-11-12T20:01:48.422051+00:00',
  controller: 'QuotesDone Technologies, a Dubai Sole Establishment, DET Dubai Trader License No. 1633275, Dubai, United Arab Emirates',
  customer_accounts: [],
  supplier_records: [{
    registered_by_you: true, company_name: 'ZZ DEMO Steel Trading LLC', contact_name: 'ZZ Demo Owner', signatory_name: 'ZZ Demo Owner',
    login_email: 'zz-demo-supplier@example.invalid', company_email: 'info@example.invalid', phone: '+971500000000',
    whatsapp_number: '+971500000000', website: 'https://example.invalid', street: 'Street 1', city: 'Al Quoz', emirate: 'Dubai',
    service_emirates: ['Dubai', 'Sharjah'], description: 'Structural steel supply and fabrication for fit-out and light industrial works.',
    trade_licence_number: 'ZZ-000000', licence_authority: 'DET', licence_expiry: '2027-06-24', licence_name: 'ZZ DEMO Steel Trading LLC',
    trn: null, owner_date_of_birth: null, emirates_id: null, registration: 'exempt', registration_expires: null, approval: 'approved',
    approved_at: '2026-10-02T08:00:00+00:00', rejection_reason: null, terms_version: 'v16', terms_accepted_at: '2026-10-01T19:59:00+00:00',
    terms_accepted_from_ip: '192.0.2.10', documents: ['trade-licence.pdf'], listed_since: '2026-08-01T00:00:00+00:00',
    // whatsapp_updates is leads.whatsapp_opt: 'same' | 'other' | 'none' | null (19 Nov 2026; it held 'in', which no row stores)
    where_we_found_the_listing: 'google_maps', whatsapp_updates: 'same', marketing_consent: null, marketing_consent_at: null, suspended: false, suspension_reason: null,
  }],
  requests: [],
  quotations: [],
  reveals: [],
  transactions: [],
  refunds: [],
  portal_chat: [],
  emails_we_sent: [
    { at: '2026-10-01T20:05:00+00:00', subject: 'Welcome to QuotesDone', channel: 'email',
      text: 'Thank you for your reply.\n\nTo register, open the link below and sign in with this e-mail address.\n- Upload your trade licence\n- Confirm your services\n\nThe QuotesDone team' },
  ],
  emails_not_sent: 2,
  emails_total: 1,
  emails_we_received: [],
  company_files: [{ file_name: 'trade-licence.pdf', kind: 'licence', at: '2026-10-01T19:00:00+00:00' }],
  data_requests: [{ kind: 'export', status: 'completed', at: '2026-11-01T08:00:00+00:00', completed_at: '2026-11-01T08:00:01+00:00' }],
  whatsapp_total: 2,
  whatsapp_withheld: 1,
  // 20:27 UTC on 28 July is 00:27 on 29 July in Dubai (UTC+4): the date crosses midnight.
  whatsapp: [
    { at: '2026-07-28T20:27:43.938602+00:00', received: 'Hi', replied: 'Hi there! Welcome to QuotesDone 👋 Just to help you better, are you a customer or a supplier?' },
    { at: '2026-07-29T06:10:00+00:00', received: 'مرحبا، نحن مورد حديد في دبي', replied: 'Thank you. You can register here:\nhttps://quotesdone.com/supplier' },
  ],
  opt_out: null,
};

export const CUSTOMER_EXPORT = {
  email: 'zz-demo-customer@example.invalid',
  generated_at: '2026-11-12T19:30:00+00:00',
  controller: SUPPLIER_EXPORT.controller,
  customer_accounts: [{
    full_name: 'ZZ DEMO Customer', email: 'zz-demo-customer@example.invalid', mobile: '+971500000001', mobile_verified: true,
    whatsapp_number: null, email_verified: true, date_of_birth: null, industry: 'Construction', language: 'en',
    opened_at: '2026-09-15T10:00:00+00:00', terms_version: 'v10', terms_accepted_at: '2026-09-15T10:01:00+00:00',
    terms_accepted_from_ip: '192.0.2.20', whatsapp_updates: null, marketing_consent: true, marketing_consent_at: '2026-09-15T10:01:00+00:00',
    suspended: false, suspension_reason: null,
  }],
  supplier_records: [],
  requests: [{ reference: 1042, created_at: '2026-10-05T07:00:00+00:00', category: 'Structural steel', summary: 'Supply of 12 t of IPE beams to Al Quoz',
    what_you_wrote: 'We need IPE 200 beams, 12 tonnes.\nDelivery to Al Quoz before 30 November.', status: 'revealed', emirate: 'Dubai', budget: 'AED 40,000', required_by: '2026-11-30' }],
  quotations: [],
  reveals: [],
  transactions: [{ revealed_at: '2026-10-08T12:00:00+00:00', request_reference: 1042, category: 'Structural steel', quotation_aed: 38500,
    reveal_fee_aed: 1155, total_charged_aed: 1155, payment: 'paid', invoice_number: 'ZZ-DEMO-0001', invoice_link: 'https://example.invalid/zz-invoice',
    refund: null, refund_aed: null }],
  refunds: [],
  portal_chat: [{ at: '2026-10-08T13:00:00+00:00', from: 'supplier', text: 'Good afternoon. Delivery is possible on 20 November.', attachment: false, delivered: true },
    { at: '2026-10-08T13:20:00+00:00', from: 'customer', text: 'Thank you 🙏', attachment: true, delivered: true },
    { at: '2026-10-08T13:25:00+00:00', from: 'customer', text: 'My number is in the file.', attachment: false, delivered: false }],
  emails_we_sent: [{ at: '2026-10-08T12:01:00+00:00', subject: 'Your reveal receipt', text: 'Your payment of AED 1,155.00 was received.', channel: 'email' }],
  emails_total: 640,
  request_files: [{ file_name: 'ground-floor-plan.pdf', kind: 'drawing', at: '2026-10-05T07:01:00+00:00', request_reference: 1042 }],
  data_requests: [],
  whatsapp_total: 0,
  whatsapp_withheld: 0,
  emails_not_sent: 0,
  emails_we_received: [],
  whatsapp: [],
  opt_out: { at: '2026-11-01T08:00:00+00:00', reason: 'unsubscribe' },
};

export const ARABIC_CUSTOMER_EXPORT = {
  ...CUSTOMER_EXPORT,
  email: 'zz-demo-arabic@example.invalid',
  customer_accounts: [{ ...CUSTOMER_EXPORT.customer_accounts[0], full_name: 'ZZ DEMO عميل تجريبي', email: 'zz-demo-arabic@example.invalid', language: 'ar' }],
  requests: [{ ...CUSTOMER_EXPORT.requests[0], category: 'حديد إنشائي', summary: 'توريد 12 طن من جسور IPE', what_you_wrote: 'نحتاج جسور IPE 200 بوزن 12 طن.\nالتسليم في القوز قبل 30 نوفمبر.' }],
  portal_chat: [{ at: '2026-10-08T13:00:00+00:00', from: 'supplier', text: 'Good afternoon. Delivery is possible on 20 November.', attachment: false },
    { at: '2026-10-08T13:20:00+00:00', from: 'customer', text: 'شكرًا لكم 👍', attachment: false }],
  whatsapp: [{ at: '2026-10-01T09:00:00+00:00', received: 'السلام عليكم', replied: 'وعليكم السلام، أهلًا بكم في QuotesDone.' }],
};
