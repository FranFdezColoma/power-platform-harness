# Description
{{project_description}}

## Where to start

Route by what the conversation is doing, not by the command typed:

- **Solutioning** (weighing how to meet a need, comparing options, "how would you do X?", without an /opsx command): before answering, read `docs/context/project.md` and `docs/solutioning/principles.md`, and `docs/context/glossary.md` when business terms come up. Apply them as for a design.md: inspect the current state in DEV read-only, climb the ladder, respect the accepted ADRs in `docs/adr/`, and close a proposal that builds something with the components table. A decision that affects architecture or project-wide conventions is written as an ADR in `docs/adr/`, Proposed until the user confirms it. Once the solution is agreed and it is more than a quick fix, offer `/opsx:propose`; do not impose it.
- **OpenSpec work** (any /opsx command): the commands load `openspec/config.yaml`, which holds the process: what each step reads, when the branch and the feature solution are created, the functional and technical gates, and what archive updates. Read it yourself before acting on a change outside a command, such as checking a gate.
- **Any other change** (a quick fix): `docs/agents/development-standards.md` is mandatory reading before any implementation: it holds the technology-agnostic rules, the Definition of Done, and the index of per-technology standards. From that index, read only the file(s) relevant to what you're about to touch.

English is mandatory for code. Everything else uses the project language: the artifact language set in `openspec/config.yaml`.

## Project context

`.power-platform/project.json` is the source of truth for the project identity and the connections it expects: the DEV environment, the tenant, the repository and its provider. Check that the `pac` profile and the `az` session you are about to use reach that environment and tenant.

## Tool usage

Never assume a tool is present or absent: check when the task needs it. Microsoft's official Dataverse and Power Platform skills do the work against Dataverse; this repository's standards set the conventions they follow. When a task depends on a fact you could check, check it instead of recalling it: skills for specialized domain knowledge, MCP servers for inspection/operations (when the tenant restricts the Dataverse MCP server, the Dataverse skills' Python SDK), `pac` (Power Platform CLI) for platform lifecycle operations, `{{repository_cli}}` for repository operations, `openspec` for the spec workflow, and official docs or web search for current Microsoft behavior, CLI syntax, SDK versions or platform capabilities.
