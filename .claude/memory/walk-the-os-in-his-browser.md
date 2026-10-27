---
name: walk-the-os-in-his-browser
description: Claude in Chrome reaches the founder's logged-in OS session — "you have my browser access, that's not an excuse". A page read is not a button audit; each page's buttons must be pressed. Working recipe and traps (6 Sep 2026).
metadata:
  type: feedback
---

6 Sep 2026: the founder rejected "nobody rendered the OS because it needs your login" — the
claude-in-chrome MCP has his session. He then asked for a deep audit "button by button" and it found
14 defects a DB-side audit could not (dead journal button, ⌘K opening nothing, Observe-mode drawer
he had rejected, two pages timing out, 96 personas shown as staff, three open-task counts...).

**Recipe:** navigate to quotesdone.com/os; `find` the sidebar buttons and click by ref right after
a reload (refs drift after the sidebar scrolls — re-`find` before each page, or click by coordinate
from a fresh screenshot); `get_page_text` for content, `read_console_messages` for errors; do not
press Approve/Reject/Save/Run now/Publish/delete/Sign out; note model-backed buttons as not
exercised. Keep a findings file in the scratchpad as you go.

**Traps:** the OS mounts every opened module as a tab and the page goes "busy" after ~15 openings
(close the tab and reopen); Vercel production lags a merge by minutes — check list_deployments
before judging a screen; the command palette could not open modules (fixed 6 Sep); a founder
command typed during a CI run trips phase_c_guards_reject_injected_defects' residue count
(identity collision, not a leak). His QuotesDone alert mailbox (management@quotesdone.com) is not
a connected mailbox — Gmail is his personal one, Outlook is doratajewelries; platform emails come
from info@quotesdone.com. See [[the-surfaces-counted-raw-status-as-his-approvals]].
