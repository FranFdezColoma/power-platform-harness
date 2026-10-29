# Solutioning Principles

Common principles for every design.md. How to build it is governed by
`docs/agents/development-standards.md`. Designs are for a live project: they go down to the
concrete component and start from what already exists in the environment.

## How to use this file
- Read it before writing or revising design.md, and in /opsx:explore when the exploration
  weighs how to solve something or needs the current system state.
- Then read the topic file for each topic the design considers, only those. Topic files live
  in `docs/solutioning/` and are listed in the index at the end of this file.
- A topic file may make a principle more specific. It MUST NOT contradict it. On a conflict,
  this file wins and the conflict is reported.
- If a topic has no file, apply this file alone and state the gap in design.md.

## design.md and tasks.md
- design.md decides; tasks.md only breaks the decisions into steps. Every choice a reviewer
  should approve at the technical gate is made in design.md: which component, of which type,
  on which table, triggered by what, synchronous or asynchronous.
- tasks.md never takes a solutioning decision. If writing a task needs one that design.md
  does not contain, design.md is incomplete: fix it there.
- design.md stays at the level of the platform. It never names projects, files, classes,
  namespaces, test frameworks or code patterns: those belong to development.
- Keep the headings of the OpenSpec template and put the content below inside them. Do not
  add, rename or reorder headings.

## Current state
Do not rely on documentation for what exists in Dataverse: before proposing anything, inspect
it, read-only, limited to what the change touches.

What to look for:
- Tables and columns that already exist and can be reused or extended.
- Solutions, security roles, and the flows and plugin steps registered on the affected tables.
- Environment variables and connection references the change could reuse.
- Accepted ADRs in `docs/adr/`.

How:
- Name the environment first: `pac org who --environment <devUrl>`, with the DEV url from
  `.power-platform/project.json`. An environment you have not verified is production.
- Solutions and records: `pac solution list --environment <devUrl>`, `dv-query`.
- Tables, columns, relationships and keys: `dv-metadata`, read only; otherwise the Dataverse
  Web API (OData), GET only.
- Never POST, PATCH or DELETE during inspection. Never print, log or commit an access token.
- Check exact syntax (`pac help`, the Web API reference); do not recall it.

Record it under Context: what exists, what the change touches, and what could not be checked
(and why).
A design that contradicts an accepted ADR does not override it: it raises an open question
("supersede ADR-NNNN?").

## Keep it simple
The simplest design that meets the specs wins. Avoid over engeneering. Every component must be needed by a spec
requirement; nothing is added for future needs, flexibility or elegance.

### The ladder
Solve each need on the first rung that covers it. Go up a rung only when the one below
cannot meet the requirement, and say why in one line. The examples on each rung are not a
closed list: consider any platform capability that fits, including new ones, and check in
Microsoft Learn what exists and whether it is generally available.

1. **Standard**: what Dataverse and the Dynamics 365 apps already do, as they do it.
   Standard tables, columns, views, forms, apps, processes, etc. Adapting the process to the
   standard is preferred over adapting the standard to the process.
2. **Customization**: configuration and low-code building. New columns and tables, forms,
   views, business rules, calculated, rollup and formula columns, business process flows,
   alternate keys, duplicate detection, security roles, model-driven and canvas apps, custom
   pages, Power Pages sites, Copilot Studio agents, etc.
3. **Automation**: only when a requirement needs something to happen without the user doing
   it. Cloud flows, desktop flows, etc.
4. **Code**: only when a platform constraint demands it (rejecting an operation or keeping
   data consistent in the transaction needs synchronous server logic) or the rung below would
   clearly be worse (high volume, complex logic, strict error handling). Plugins, Custom APIs,
   form scripts, PCF controls, code apps, virtual table providers, Azure services, etc.

### Rules
- Fewest components. Extend an existing table or component before creating one; a column
  before a table; one component per need.
- No speculative generality: no configuration tables, parameters, frameworks, generic
  engines or extension points the specs do not ask for.
- No automation for what users can do with standard features (a view, a form, a quick
  create), unless a requirement asks for it explicitly.
- When the standard almost fits, do not build around it: raise an open question proposing
  to adjust the requirement to the standard.
- Only generally available capabilities. A capability in preview is never part of a design;
  if only a preview capability would cover a need, raise it as an open question.
- Before closing Decisions, apply the removal test to every component: if removing it
  breaks no spec requirement, remove it.

## Decisions
- Each decision describes what will be built: the spec requirement it serves and the
  components it introduces or modifies. Rejected options are not listed.
- Before closing Decisions, check the change's impact on security, regulated data, licensing,
  volume and platform limits, integrations and existing data. Record each impact as a decision
  or an open question; never resolve it silently.
- A decision that affects architecture or project-wide conventions also gets an ADR in
  `docs/adr/`.

Close Decisions with a components table: the contract handed to tasks.md.

| Component | Type | Logical name | Behaviour | Decision |
| --- | --- | --- | --- | --- |
| Account credit check | Plugin, synchronous | — | Rejects Update on account when credit limit is exceeded; message Update, stage PreValidation | D-02 |

Logical names use the prefix in `.power-platform/project.json`. Do not assign components to
solutions: the development standards decide that from the branch.

## Assumptions and open questions
- What could not be decided is an assumption with a recommended default and a question for
  the client, under Open Questions.
- An assumption that would change the architecture is marked **blocking**. A design with an
  open blocking assumption is not ready for the technical gate.

## References
- Microsoft Learn is the reference for what the platform offers and how it behaves. Use the
  Microsoft Learn MCP server if available; otherwise search restricted to learn.microsoft.com.
- For decisions that affect architecture, also check the recommended patterns in the
  Dynamics 365 implementation guide (Success by Design), on Microsoft Learn.
- Platform limits, licensing requirements and preview or general-availability status are
  checked there and cited inline, next to the claim, with their source. What cannot be
  checked is marked unverified. Never quote prices.

## Topic index
| Topic | File |
| --- | --- |
