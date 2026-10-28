# Development Standards

Rules that apply to every change in this repository, whatever the technology.

## Before starting a unit of work

Every feature, fix or chore is developed on its own branch and, when it touches Dataverse components, in its own feature solution named after that branch. So before the first change of a unit of work, ask the user whether it goes on the current branch or on a new one, and wait for the answer. `docs/development/solutions.md` holds the naming rules and the commands; follow them rather than improvising.

## How to use this file

- A technology file may make a rule here more specific. If it contradicts one, this file wins and you report the contradiction.
- If the change touches a technology with no standards file, apply this file alone and state that gap explicitly in the final report.
- Project identity: project `{{project_name}}`, publisher `{{publisher_unique_name}}` with customization prefix `{{publisher_prefix}}`, core solution `{{core_solution}}` in DEV (`none` when the project has none). The project name is also the root .NET namespace.
- Only when a tool a task needs is missing or fails, read `docs/agents/toolchain.md` for what the machine needs; the harness's `setup-tools` skill installs it. Never assume a tool is present or absent: check when the task needs it.
- Versions: the standards name no package or SDK version that would go stale. When a new project needs a pin (a NuGet package, an npm dev dependency, an MSBuild SDK), look up the latest stable release at its official source (NuGet, npm, the vendor's documentation) and pin that exact version. A project that already pins a version keeps it; upgrading is its own change, never alongside unrelated work.

## Design principles

- Do not introduce abstractions until there is a demonstrated need. Two call sites are not a need; three divergent ones might be.
- Change only what the task requires. No opportunistic refactors, renames, formatting sweeps or dependency bumps riding along with a functional change: they hide the real diff from the reviewer.
- Never introduce a new technology, framework, library, architectural pattern, testing framework or project convention when an equivalent project standard already exists.
- Choose the technology by what the requirement needs from the platform:
  - Rejecting an operation, or keeping data transactionally consistent: a plugin. A cloud flow runs after the commit and cannot prevent anything.
  - Interface behaviour and immediate user feedback: a JavaScript web resource or a PCF control.
  - Asynchronous work, integrations, notifications, approvals and scheduled work: a cloud flow.
  - Where more than one would genuinely work, prefer the one whose failure mode is cheaper to live with.
- When nothing here decides it: check the existing codebase, then this repository's docs and skills, then relevant MCPs and official Microsoft documentation. Prefer the established project pattern over a generic best practice.
- Record a decision in `docs/adr/` before implementing it whenever it affects architecture or project-wide conventions — including one resolved through the fallback above.

## Business logic separation

- Express a business rule independently of the platform whenever the rule can be stated without it.
- Pure business rules take and return plain values, are deterministic and side-effect free. Pass non-deterministic inputs (current time, GUIDs, random values, current user) as parameters.
- Platform APIs, context objects and I/O belong in the integration layer, never inside the rule.
- Separate a rule when it has branches or needs its own tests. A single check with no branching stays inline.

## Error handling

- Never swallow a failure. Silent success after an error is the most expensive defect class in this stack: it produces inconsistent data that nobody is alerted to.
- Expected business or validation failures produce a user-safe message: no stack traces, no internal identifiers, no implementation details.
- Unexpected failures propagate. Do not convert them into a success result or a default value.
- Validate as early as the platform allows, and fail before writing anything.
- Never leave a record, form or process in a half-applied state after a failure.

## Data, secrets & traceability

- Never hardcode connection strings, API keys, secrets, credentials, environment-specific URLs or endpoints, or environment GUIDs in code, configuration, flows, tests or fixtures. Use environment variables and connection references.
- Never commit or log personally identifiable information or other regulated data (GDPR, HIPAA, PCI-DSS, etc.). Test fixtures use synthetic or anonymised data.
- Ordinary CRM data (names, emails, phone numbers, addresses of contacts and accounts) is the normal subject of this work and needs no flag. Flag it to the developer instead of proceeding silently when a task requires handling special-category data (health, biometric or genetic data, religious or political beliefs, sexual orientation, criminal records), payment card data, or government identifiers.
- Emit enough diagnostic detail to reconstruct what happened: the operation, the record identifier, the outcome. Never the contents of sensitive fields.
- Remove temporary debugging output before the change is done.

## Performance & platform limits

- Never block the user interface. Work that is not needed to render happens after first render, or outside the request entirely.
- Retrieve only the columns and rows the operation needs. No unbounded queries; page explicitly.
- Prefer data already available in context (form values, trigger payload, registered images, framework context) over retrieving the same data again.
- Never query inside a loop when a single filtered query answers the same question.
- Design within the platform limits: a sandboxed plugin is killed after 2 minutes, so long-running work goes asynchronous; an `ExecuteMultiple` batch holds at most 1000 requests; the service protection limits throttle a user with HTTP 429, so bulk clients honour `Retry-After` instead of retrying immediately.

## Language

- English for all technical work and artifacts.

## Testing

- Production code and the tests it requires are created or updated in the same change.
- Work test-first. Before any production code, a subagent writes the tests from the spec, the public surface the change exposes and the applicable standards file, so the tests encode the requirement rather than the implementation's assumptions. Run them and confirm each one fails for the reason the spec gives (*red*); then write the production code that makes them pass (*green*). A bug fix starts with a test that reproduces the bug. Without subagents, write the tests yourself, still before the production code.
- Tests execute the production artifact. They never duplicate, reimplement or paraphrase the logic under test.
- Test observable behaviour through the public surface, not implementation details.
- Cover expected behaviour, the relevant edge cases, and the failure paths.
- Tests are independent of execution order and of state left behind by another test.
- A change is incomplete while a required test is missing or failing.
- Testing in this repository means unit tests for code: plugins, Custom APIs, web resources and PCF controls. Low-code components — flows, forms, views, schema, security, solution configuration — are outside its scope.

## Working against Dataverse

- Never simulate metadata, tables, columns, relationships, solution components or environment state when a tool can retrieve it. Retrieve it with the official Dataverse skills (`dv-metadata`, `dv-query`, `dv-solution`); `dv-overview` states the same rule.
- Name the environment before any operation against it (`pac org who --environment <devUrl>`, with the DEV url from `.power-platform/project.json`). Treat any environment you have not verified as production.
- Write operations are permitted in DEV only, through the official skills, and always into the solution `docs/development/solutions.md` names. Irreversible operations — deleting a table, column, relationship, record or solution, or changing the data type of a populated column — are prepared by the agent and executed by a human.

## Blocked commands

- When a command is denied, do not reach it another way (a different spelling, a script, a subshell). Prepare the command and hand it to the developer.
- Never edit `.claude/settings.json` to get past a block.

## Reporting

- Report what you could not run, and why, alongside what you did run. A failing test is reported with its output, never summarised as an obstacle.

## Definition of Done

Compiling is not done. A task is complete only when all of the following hold:

- The implementation matches the spec and every applicable standards file.
- The unit tests the change requires exist and pass; affected projects build with no errors and no new warnings; linting and static analysis are clean.
- You re-read your own diff against the spec and the standards before reporting the task done.
- No secrets, credentials or regulated data are hardcoded, logged or committed.

## Git

- Commit only once the change satisfies the Definition of Done above — never leave a commit as the final state of a task in a broken or partially-implemented condition.
- Commit messages describe the change and its motivation, not just the action (`fix`, `update` alone are not enough).
- Branch naming: `<type>/<short-description>` (e.g. `fix/`, `feature/`, `chore/`).
- One unit of work, one branch, one feature solution, except on the trunk, which has no feature solution: `docs/development/solutions.md` says which solution applies there.

## Standards index

Read the file for each technology the change touches, before writing.

| Technology | File |
| --- | --- |
| JavaScript web resources | `docs/development/javascript.md` |
| WebResources build project | `docs/development/webresources-project.md` |
| C# Dataverse plugins | `docs/development/csharp-plugins.md` |
| PCF controls | `docs/development/pcf.md` |
| Custom APIs | `docs/development/custom-apis.md` |
| Dataverse schema | `docs/development/dataverse-schema.md` |
| Solutions and DEV environment | `docs/development/solutions.md` |
