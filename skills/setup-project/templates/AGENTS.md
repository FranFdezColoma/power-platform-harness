# Description
{{project_description}}

## Development standards

`docs/agents/development-standards.md` is mandatory reading before any change: it holds the technology-agnostic rules, the Definition of Done, and the index of per-technology standards. From that index, read only the file(s) relevant to what you're about to touch; don't preload the others.

## Official skills

Microsoft's Dataverse and Power Platform skills supply the capabilities (connecting, metadata, data, the solution lifecycle, model-driven apps, flows); this repository's standards supply the conventions. Before following an official skill's rule on the folder layout, testing, or importing a solution, read `docs/agents/skill-exceptions.md`: it lists every official rule this project overrides, quoted verbatim. Any other conflict between a standard and an official skill is a defect: report it rather than pick a side.

## Project context

`.power-platform/project.json` is the source of truth for the project identity and the connections it expects: the DEV environment, the tenant, the repository and its provider. Check a session against it before using it.

## Tool usage

When a task depends on a fact you could check, check it instead of recalling it: skills for specialized domain knowledge, MCP servers for inspection/operations, `pac` (Power Platform CLI) for platform lifecycle operations, `{{repository_cli}}` for repository operations, and official docs or web search for current Microsoft behavior, CLI syntax, SDK versions or platform capabilities.
