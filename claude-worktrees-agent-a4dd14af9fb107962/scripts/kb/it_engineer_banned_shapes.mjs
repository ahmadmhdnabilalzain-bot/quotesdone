// THE SIX SHAPES THE IT ENGINEER KNOWLEDGE BODY MAY NOT CONTAIN.
//
// This file holds ONLY the patterns, and it has no side effects: no database connection, no argv
// reading, no file reading. That is the entire reason it exists as its own module.
//
// The loader (load_it_engineer_knowledge_pack.mjs) enforces these at ingest. The eval
// (it_engineer_knowledge_retrieval_eval.mjs) proves they fire, by running THIS array against
// strings that deliberately carry each shape. Both import from here rather than one importing the
// other, because the loader is an executable script whose top level connects to the database and
// runs a load: importing it to borrow a constant would run a load as a side effect.
//
// A COPY IN THE EVAL WOULD PROVE THE WRONG THING. It would show that a copy of the guard bites,
// which is a different claim from the guard biting, and it would drift the first time one side is
// edited. That is the failure the corpus itself calls an instrument measuring the wrong subject,
// so it is not committed here.
//
// WHY THESE SIX. The session that authored the knowledge body could not read a vulnerability feed
// and cannot re-read one later, so any advisory identifier, severity score, version-specific
// vulnerability claim or patch-level assertion written into it would have been invented at the
// moment of writing. A stale security claim is worse than no claim: it carries a specific number
// and is acted on with confidence.
//
// WHAT IS DELIBERATELY NOT BANNED: the word CVE, the word vulnerability, and the concept of a
// published advisory. A record explaining HOW to determine whether an advisory reaches this estate
// is exactly what the seat needs. The identifier is banned; the noun is not.
//
// These will not catch every possible way of writing an unverifiable security claim, and that is
// not claimed. They are a tripwire for the six specific shapes an invented one takes.

export const BANNED_SHAPES = [
  [/\bCVE-\d{4}-\d{4,7}\b/i,
   'a CVE identifier -- this session cannot read a vulnerability feed, so a specific one is invented'],
  [/\bGHSA-[a-z0-9]{4}-[a-z0-9]{4}-[a-z0-9]{4}\b/i,
   'a GitHub Security Advisory identifier -- same problem as a CVE number'],
  [/\bCVSS\b[^.]{0,20}\d/i,
   'a CVSS score -- a severity number this body cannot have computed or verified'],
  [/\b(?:vulnerab\w*|exploitab\w*|unpatched|patched|remediat\w*|affected|unaffected)\b[^.]{0,60}\bv?\d+\.\d+(?:\.\d+)?\b/i,
   'a version-specific vulnerability or patch claim (vulnerability word, then a version number)'],
  [/\bv?\d+\.\d+(?:\.\d+)?\b[^.]{0,60}\b(?:is|are|was|were|remains?)\s+(?:not\s+)?(?:vulnerab\w*|exploitab\w*|affected|patched|unpatched)\b/i,
   'a version-specific vulnerability or patch claim (version number, then a vulnerability word)'],
  [/\b(?:we|this estate|the (?:cluster|runtime|instance|platform|project|database))\s+(?:is|are)\s+(?:currently\s+)?(?:on|running)\b[^.]{0,40}\d+\.\d+/i,
   'an assertion about the patch level this estate is running -- read it from the platform, never from a record'],
];

// Returns the description of the FIRST banned shape found, or null. Callers report the description
// rather than the pattern, so a refusal says what was wrong rather than showing a regular expression
// to whoever has to fix the record.
export const firstBanned = (t) => (BANNED_SHAPES.find(([re]) => re.test(t)) || [null, null])[1];
