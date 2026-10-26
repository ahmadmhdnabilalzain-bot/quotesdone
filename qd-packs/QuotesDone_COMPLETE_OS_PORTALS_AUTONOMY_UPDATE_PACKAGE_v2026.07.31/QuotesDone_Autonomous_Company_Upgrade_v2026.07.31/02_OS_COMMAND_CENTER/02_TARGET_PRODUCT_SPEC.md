# Executive OS target product specification

## Executive Home

One screen with:

- Company health and data-quality indicator.
- Revenue, burn, runway and AI cost.
- Customer/supplier/RFQ/quote/reveal funnel.
- Marketplace health and category coverage.
- Active incidents and bottlenecks.
- Work completed autonomously.
- Exceptions requiring founder attention.
- Top opportunities and risks.
- Current strategic objectives and progress.

Every number must expose source, calculation, timestamp and confidence/freshness.

## Executive Conversation

The founder can ask questions or issue objectives. The response must contain:

- answer/recommendation;
- evidence;
- assumptions;
- alternatives;
- expected impact;
- confidence;
- cost;
- proposed actions;
- required authority.

Commands that mutate data follow **preview -> authority check -> execution -> trace -> outcome**.

## Live Company

A real-time stream of canonical business events grouped by workflow/correlation ID. The UI should show a readable summary, affected entities, responsible OS/employee, outcome and links to evidence.

## Organization and Employee Workspace

Show role, manager, direct reports, responsibilities, authority, KPIs, goals, workload, current tasks, recent decisions, knowledge used, memory, learning, reliability and cost efficiency.

## Trace Explorer

For any decision/action:

- trigger;
- actor;
- workflow;
- data and knowledge used;
- policies and authority;
- alternatives;
- confidence;
- side effects;
- downstream events;
- measured outcome.

## Simulation

Simulations must separate facts from assumptions and support best/base/downside cases. Never show fake precision.

## Navigation

Use command-first interaction, but retain accessible routes and keyboard navigation. Do not make the product unusable without AI.

## Visual priority

1. Clean 2D workspace and graph.
2. Smooth transitions and live state.
3. Optional spatial/3D views only after core operations are proven.
