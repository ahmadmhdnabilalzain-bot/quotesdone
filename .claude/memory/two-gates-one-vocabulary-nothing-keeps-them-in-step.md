---
name: two-gates-one-vocabulary-nothing-keeps-them-in-step
description: "When a value must be registered in two places for a thing to work, find what keeps them in step — usually nothing, and the drift surfaces as a scary-looking refusal aimed at the wrong person."
metadata: 
  node_type: memory
  type: feedback
  originSessionId: 66a952a6-eec2-4b4b-9915-b04839a8d384
  modified: 2026-08-13T11:23:10.367Z
---

An os_api action must appear in **both** `ACTION_CLASS` (code) and `public.control_mode_action`
(database). Each gate refuses independently — deliberate, and documented in os_api. Nothing kept
them in step. Measured 13 Aug 2026: code 73, database 90, **11 in the code the database had never
heard of**.

The symptom was not quiet, it was *aimed at the wrong person*: the database gate refuses an
unregistered action with `action_classification_required`, and the console renders that as the
**Control Mode panel** — an MFA challenge with a "why are you making this change?" box. Eight of the
eleven were `read_only`. Opening System Health asked the founder for a code sent to his phone in
order to *look at a dashboard*.

**That is what "remove the texting gate" meant.** It was never the login — see
[[no-observe-mode-plain-login]], which read as an auth complaint and was actually this. Fixed by
registering the eleven (#325) and by making the existing check read the second list (#326); its own
header had said "add it to both" for weeks while comparing the code only to itself.

**How to apply:** when a thing must be registered twice, ask *what fails if only one is done* and
*what keeps them in step*. If the answer to the second is "a sentence in a comment", the drift has
probably already happened — go and diff the two lists. Then check whether the resulting refusal is
shown to a human as something other than what it is.

**Related trap, same session:** `control_mode_action.requires_control` is a GENERATED column derived
from `classification`, so those two *cannot* drift. That is the pattern to copy — make the second
value derivable rather than separately maintained. Postgres refused my hand-written insert and was
right.
