# Fix round after the final audit, 12 Nov 2026

The audit itself is in `../2026-11-12-final-audit.md`. These are the reports written while its findings
were being fixed (founder rulings 1642 to 1648). Text only: the screenshots of the walk (142 MB) were
session scratch and are not in git, per the README one level up.

| file | what it is |
|---|---|
| `registration-perfection-walk.md` | The browser walk of supplier registration at phone and desktop widths against ruling 1645 ("I'm looking for perfection"). Findings B1, H1 to H10, M and L rows. |
| `whatsapp-paid-recheck.md` | The paid re-check of WhatsApp after #1953: what was fixed, the double answer it found (fixed in #1958), and the speed and wording findings R3 to R13. |
| `five-minute-mark-relay-hold.md` | The measurement that edge-function calls arriving in the first seconds after each five-minute mark wait 1.6 to 4 s before our code runs, with the note for Supabase support. |

Paths beginning `/tmp/claude-0/` inside these files point at the session's scratch folder, which no
longer exists; the finding beside each path is the record.
