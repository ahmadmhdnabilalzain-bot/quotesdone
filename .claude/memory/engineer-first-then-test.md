---
name: engineer-first-then-test
description: "Proper engineering order — define the standard, checklist it, compare to what is built, build the gaps, THEN test. Never discover requirements by failing tests."
metadata:
  node_type: memory
  type: feedback
  originSessionId: 8c4972a3-8a16-4cb0-a308-31a4f45e00bb
  modified: 2026-09-28T13:06:32.914Z
---

Founder, 28 Sep 2026, on my plan to "test customer support with 120 conversations": *"before you even do any test… did you really check the infrastructure? What defines a proper customer support agent? What are the standards?… you make a checklist. You compare to what you built, and if anything is missing, you build it. And then, if the infrastructure is good, a test is just a test… doing it the other way around, it's totally wrong… this is valid for everything."*

**Why:** when a test comes first, requirements only surface one at a time as tests fail. That is reverse engineering pretending to be a build. It wastes cycles, and it never produces a complete system.

**How to apply,** for every capability (a seat, a feature, a journey):
1. **Define the standard.** Set out what a world-class version is: its capabilities, behaviours and features, from real-world practice and sources.
2. **Write the checklist** from that standard.
3. **Audit what is built** against the checklist, with evidence for each item.
4. **Build every gap.**
5. **Only then test.** The test confirms what was built.
6. **When a test fails,** troubleshoot and analyse. Reverse engineering is for diagnosing faults, never for discovering requirements.

When a user asks "test X", answer with the standard and the gap list first. Related: [[customer-support-better-than-amazon]], [[agents-are-expert-human-staff-who-act]].
