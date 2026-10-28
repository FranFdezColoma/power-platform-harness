# Description
{{project_description}}

## Where to start

- **OpenSpec work** (any /opsx command): `docs/agents/openspec-workflow.md` is mandatory reading first. It says what each step reads, when the branch and the feature solution are created, and the functional and technical gates.
- **Any other change** (a quick fix): `docs/agents/development-standards.md` is mandatory reading before any implementation: it holds the technology-agnostic rules, the Definition of Done, and the index of per-technology standards. From that index, read only the file(s) relevant to what you're about to touch.

English for everything in the repository, except OpenSpec artifacts, which use the artifact language set in `openspec/config.yaml`.

## Microsoft official skills

Use Microsoft's Dataverse and Power Platform skills when needed to do the work against Dataverse. This repository's standards set the conventions and guidelines for coding.

## Project context

`.power-platform/project.json` is the source of truth for the project identity and the connections it expects: the DEV environment, the tenant, the repository and its provider. Check a session against it before using it.

## Tool usage

When a task depends on a fact you could check, check it instead of recalling it: skills for specialized domain knowledge, MCP servers for inspection/operations (when the tenant restricts the Dataverse MCP server, the Dataverse skills' Python SDK), `pac` (Power Platform CLI) for platform lifecycle operations, `{{repository_cli}}` for repository operations, `openspec` for the spec workflow, and official docs or web search for current Microsoft behavior, CLI syntax, SDK versions or platform capabilities.
