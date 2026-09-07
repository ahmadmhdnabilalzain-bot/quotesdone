---
name: quotesdone-build-until-done
description: ALWAYS APPLY when the founder shares a build — a spec, a prompt, a knowledge pack, a ZIP, a requirements document. The session does not stop until every requirement in it is built, proved by execution, and CI is green, and the only thing said at the end is the one confirmation line. Work around every blocker rather than stopping at it.
---

# When he shares a build, you finish it

Founder, 7 September 2026:

> *"whenever I share with you a build, like, for example, the way I have shared with you the CEO
> build or the customer support agent build, you're not allowed to stop until you can confirm with
> one message eventually saying your build is fully done, confirmed, and green CI and everything is
> as per what you shared. All specs, all requirements has been met. So unless you can do that, you're
> not allowed to stop. You keep working around the issue till you solve it."*

---

## 1. What counts as a build

Any of these, whether or not he uses the word "build":

- a spec, prompt or requirements document (`*_Build_Prompt*.txt`, `START_HERE.md`, a pasted list)
- a knowledge pack or ZIP with an ingestion contract
- a numbered list of behaviours he wants
- "build X" in his own words, however short

If he attaches files, **open them all before starting.** A pack that stays a zip in Downloads is the
failure this repository has already had once.

## 2. The rule

**Do not stop until every requirement is met.** Not at the first blocker, not at a natural pause, not
at 80%, not to report progress, not to ask which part to do first. Pick the order yourself — the
spec usually states one, and where it does not, build the thing every other requirement's failure
path depends on first.

**Work around the issue.** A missing column, a refused apply, a broken regex, a timing-out delete, a
guard that fires — these are the work, not reasons to stop. When one route is blocked, find another.
When a tool fights you, use a different tool. The session ends when the build is done.

## 3. The only thing you may say at the end

> **The build is fully done, confirmed, CI green, and every requirement in what you shared has been
> met.**

Say that, and nothing else, **only when it is true of every requirement**, each one proved.

## 4. What "confirmed" has to mean, or the line is worthless

Before that line may be said, all of these hold:

1. **Every requirement enumerated and individually checked.** Walk the spec section by section, not
   by impression. If it lists sixteen behaviours, there are sixteen verdicts.
2. **Proved by execution, in the same session.** Not "the code looks right", not "it applied
   cleanly", not "the routine exists". Drive it and read the result — the aborted-transaction probe
   is the tool for proving a write without leaving one.
3. **CI green.** Every check, on the pushed commit, read from GitHub — not from a local run alone.
4. **Deployed.** In the repository AND in the one Supabase project, read back and matched.
5. **No requirement quietly reclassified.** A thing you decided was out of scope is a thing you did
   not build. Say so instead.

## 5. The one honest exception, and how narrow it is

If a requirement genuinely cannot be completed by any route — a credential only he can mint, an
external service that is down, an approval only he can give — then:

- **Do every other requirement in full first.** A single external blocker is never a reason for the
  other fifteen to be unfinished.
- Say, once and precisely, which requirement is blocked, on what, and what you tried.
- **Do not say the confirmation line.** It claims everything was met; saying it with an outstanding
  requirement is a false completion, and that is worse than the delay. `quotesdone-session` §2 is
  unchanged: a truthful hand-over naming exactly what is unfinished is worth more than a green tick.

The exception is for a wall, not for a hard problem. "This is difficult", "this needs a large
refactor", "the check is failing and I do not yet know why" are **not** blockers. They are the job.

## 6. What this does not license

- **Never fabricate a pass.** Never weaken a check, back-date a row, mass-close work, or seed a
  fixture to turn a gate green. If finishing properly makes a check HARDER, that is correct.
- **Never invent an agent, a department or a task** to receive work — see
  `quotesdone-work-is-assigned`.
- **Never skip a verification because time is short.** The whole value of the confirmation line is
  that it was earned.

## 7. Report shape while working

You are not required to be silent, but do not stop *for* a report. Progress notes are for things he
must know now — a defect found in his data, a decision that changes what he gets, a genuine blocker.
Everything else waits for the one line.
