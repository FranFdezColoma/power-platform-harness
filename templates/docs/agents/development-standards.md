# Development Standards

Rules that apply to every change in this repository, whatever the technology.

## Before starting a unit of work

Every feature, fix or chore is developed on its own branch and, when it touches Dataverse components, in its own feature solution named after that branch. So before the first change of a unit of work, ask the user whether it goes on the current branch or on a new one, and wait for the answer. `docs/development/solutions.md` holds the naming rules and the commands; follow them rather than improvising.

## How to use this file

- Read this file before any change. Then read the standards file for each technology the change touches — only those, not all of them.
- A technology file may make a rule here more specific. It MUST NOT contradict it. On a genuine conflict, this file wins and the conflict is reported.
- If the change touches a technology with no standards file, apply this file alone and state that gap explicitly in the final report.
- Project identity: project `{{project_name}}`, publisher `{{publisher_unique_name}}` with customization prefix `{{publisher_prefix}}`, core solution `{{core_solution}}` in DEV (`none` when the project has none). The project name is also the root .NET namespace.
- Only when a tool a task needs is missing or fails, read `docs/agents/toolchain.md` for what to install. Never assume a tool is present or absent: check when the task needs it.

## Design principles

- Prefer the simplest solution that satisfies the requirement. Avoid over-engineering.
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
- Do not force this separation onto logic that is already simple.

## Error handling

- Never swallow a failure. Silent success after an error is the most expensive defect class in this stack: it produces inconsistent data that nobody is alerted to.
- Expected business or validation failures produce a user-safe message: no stack traces, no internal identifiers, no implementation details.
- Unexpected failures propagate. Do not convert them into a success result or a default value.
- Validate as early as the platform allows, and fail before writing anything.
- Never leave a record, form or process in a half-applied state after a failure.

## Data, secrets & traceability

- Never hardcode connection strings, API keys, secrets, credentials, URLs, endpoints or environment GUIDs in code, configuration, flows, tests or fixtures. Use environment variables and connection references.
- Never commit or log personally identifiable information or other regulated data (GDPR, HIPAA, PCI-DSS, etc.). Test fixtures use synthetic or anonymised data.
- If a task appears to require handling a regulated data category, flag it to the developer instead of proceeding silently.
- Emit enough diagnostic detail to reconstruct what happened: the operation, the record identifier, the outcome. Never the contents of sensitive fields.
- Remove temporary debugging output before the change is done.

## Performance & platform limits

- Never block the user interface. Work that is not needed to render happens after first render, or outside the request entirely.
- Retrieve only the columns and rows the operation needs. No unbounded queries; page explicitly.
- Prefer data already available in context (form values, trigger payload, registered images, framework context) over retrieving the same data again.
- Never query inside a loop when a single filtered query answers the same question.
- Respect platform limits by design: sandbox timeouts, API request limits, throttling, message size.

## Naming & language

- English for all technical work and artifacts.
- Respond in the user's language unless requested otherwise.

## Testing

- Production code and the tests it requires are created or updated in the same change.
- Tests execute the production artifact. They never duplicate, reimplement or paraphrase the logic under test.
- Test observable behaviour through the public surface, not implementation details.
- Cover expected behaviour, the relevant edge cases, and the failure paths.
- Tests are independent of execution order and of state left behind by another test.
- A change is incomplete while a required test is missing or failing.
- Write the test first where you can: it is the recommended practice, not a condition of done.
- Testing in this repository means unit tests for code: plugins, Custom APIs, web resources and PCF controls. Low-code components — flows, forms, views, schema, security, solution configuration — are outside its scope.

## Working against Dataverse

- Never simulate metadata, tables, columns, relationships, solution components or environment state when a tool can retrieve it. Use the Dataverse MCP server or `pac`.
- Name the environment before any operation against it (`pac org who`). Treat any environment you have not verified as production.
- Write operations are permitted in DEV only, with `pac` or the Dataverse MCP server, and always into the solution `docs/development/solutions.md` names. Irreversible operations — deleting a table, column, relationship, record or solution, or changing the data type of a populated column — are prepared by the agent and executed by a human.

## Reporting

- Report what you could not run, and why, alongside what you did run. A failing test is reported with its output, never summarised as an obstacle.

## Definition of Done

Compiling is not done. A task is complete only when all of the following hold:

- The implementation matches the spec and every applicable standards file.
- The unit tests the change requires exist and pass; affected projects build with no errors and no new warnings; linting and static analysis are clean.
- The diff was reviewed against the spec and the standards.
- No secrets, credentials or regulated data are hardcoded, logged or committed.

## Git

- Commit only once the change satisfies the Definition of Done above — never leave a commit as the final state of a task in a broken or partially-implemented condition.
- Commit messages describe the change and its motivation, not just the action (`fix`, `update` alone are not enough).
- Prefer `gh` for PR creation, review and inspection over the web UI.
- Branch naming: `<type>/<short-description>` (e.g. `fix/`, `feature/`, `chore/`).
- One unit of work, one branch, one feature solution, except on the trunk, which has no feature solution: `docs/development/solutions.md` says which solution applies there. Before starting anything, ask whether the work goes on the current branch or a new one, and derive the feature solution name from the branch: `docs/development/solutions.md` owns that flow and its commands.

## Standards index

Read the file for each technology the change touches, before writing.

| Technology | File | Status |
| --- | --- | --- |
| JavaScript web resources | `docs/development/javascript.md` | Ready |
| WebResources build project | `docs/development/webresources-project.md` | Ready |
| C# Dataverse plugins | `docs/development/csharp-plugins.md` | Ready |
| PCF controls | `docs/development/pcf.md` | Ready |
| Custom APIs | `docs/development/custom-apis.md` | Ready |
| Dataverse schema | `docs/development/dataverse-schema.md` | Ready |
| Solutions and DEV environment | `docs/development/solutions.md` | Ready |
