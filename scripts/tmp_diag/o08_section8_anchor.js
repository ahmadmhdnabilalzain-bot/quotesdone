// The section-8 NOT_RUN list, before and after. Kept as data rather than as an inline template so
// the SQL quoting inside it is not fighting a shell, a heredoc and a JS escape at the same time.
const FIND = `      ('PD-PRIV-004','PRIVACY: needs a supplier bearer token calling the raw inquiry endpoint and the response body.'),
      ('PD-PRIV-005','PRIVACY: needs a rendered artifact to scan for hidden metadata; no Phase D path renders one.'),
      ('PD-PRIV-002','PRIVACY: needs a drawing revision with an unapproved redaction; file revision state is a storage + document-pipeline fact.'),
      ('PD-QUOTE-001','QUOTE: needs supplier A''s token editing supplier B''s quote over the API.'),
      ('PD-QUOTE-004','QUOTE: needs a customer read of an unpublished quote through the portal read path.'),
      ('PD-LEGAL-004','LEGAL: needs the tax/legal static file freshness check, which is a content-pipeline fact.')
`;

const REPL = `      ('PD-PRIV-004','PRIVACY: needs a supplier bearer token calling the raw inquiry endpoint and the response body.')
`;

module.exports = { FIND, REPL };
