# Toolchain

The tools this repository expects on a developer machine, and what each one is for. This file states no versions on purpose, except the .NET SDK's floor, which the `.slnx` solution format sets: what counts as supported or current changes faster than this file does. When a task needs a tool, check the installed version against its official source (release notes, the support policy, the official skill that depends on it) and recommend an update when it is unsupported or clearly behind. The target frameworks and package versions the code uses are the project's, stated in `docs/development/*.md` and in the project files themselves.

Tool availability belongs to the machine, not to the repository. Check what is available when a task needs it — `Get-Command pac`, the MCP servers registered with the agent — and never assume a tool is present or absent. Installing and updating them is the harness's `setup-tools` skill's job, and signing in is its `connect` skill's; Python's packages, the Dataverse MCP server and `.env` are `dv-connect`'s.

## Required

| Tool | What needs it |
| --- | --- |
| PowerShell | The terminal on Windows; `pac` and PCF tooling |
| git | One branch per unit of work |
| .NET SDK 10 or later | Building and testing plugins and Custom APIs; the solution file is `.slnx` |
| Node.js | Testing and linting web resources and PCF controls; the official skills' hooks and MCP servers |
| Power Platform CLI (`pac`) | Code generation, solution operations, environment access |
| Python | The Dataverse skills' scripts (`scripts/auth.py`) and Python SDK |
| OpenSpec CLI (`openspec`) | The spec workflow: `/opsx` commands, `openspec update` to refresh the generated skills |
| Azure CLI (`az`) | The model-apps and power-automate skills; a token source for the Dataverse skills' Python SDK |

The Dataverse MCP server is often restricted at tenant level. Without it, the Dataverse skills reach DEV through their Python SDK, and `scripts/auth.py` can take its token from a signed-in `az` session in the project's tenant (`connections.dataverse.tenantId`): `az account show` says which tenant, and the user signs in with `az login --tenant <tenantId>`. Where the installed skills offer it, `python scripts/auth.py --diagnose` shows which credential source the next call will use, without prompting.

A minimum stated by an official skill (in its README or plugin manifest) is a requirement; read it there rather than copying it here.

Keep one `pac` installation: two (the Windows installer and the .NET global tool, say) shadow each other on PATH, and a command may run a version other than the one you checked.

`pac` also needs an authentication profile that reaches DEV: the harness's `connect` skill creates it, named after the project, and `pac org who --environment <dev-url>` confirms which environment a command reaches. `pac pcf init` and `pac modelbuilder` generate project structure and early-bound classes; there is no acceptable manual equivalent. Never hand-write what these commands generate. Plugin projects are the exception: they are not created with `pac plugin init`, but from the `.csproj` in `docs/development/csharp-plugins.md`.

## Per repository

| Tool | When | What it adds |
| --- | --- | --- |
| GitHub CLI (`gh`) | The repository is on GitHub | Pull requests and repository operations from the terminal |
| `az` `azure-devops` extension | The repository is on Azure DevOps | `az repos` and `az devops`: pull requests and repository operations |

`.power-platform/project.json` names the provider (`connections.repository.provider`).

## Recommended

| Tool | What it adds | Without it |
| --- | --- | --- |
| Dataverse MCP server | Reading metadata and records, and writing in DEV, from the agent | The Dataverse skills' Python SDK, `pac`, or the maker portal |
| `playwright-cli` | Manual checks of PCF controls and web resources in their DEV forms | A manual check in the browser |

`dv-connect` registers the Dataverse MCP server; `setup-tools` installs `playwright-cli` and its skill; the CLI suits coding agents because it loads no tool schemas or accessibility trees into context.
