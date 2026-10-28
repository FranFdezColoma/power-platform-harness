# Toolchain

The tools this repository expects on a developer machine, and what each one is for. This file states no versions on purpose: what counts as supported or current changes faster than this file does. When a task needs a tool, check the installed version against its official source (release notes, the support policy, the official skill that depends on it) and recommend an update when it is unsupported or clearly behind. The target frameworks and package versions the code uses are the project's, stated in `docs/development/*.md` and in the project files themselves.

Tool availability belongs to the machine, not to the repository. Check what is available when a task needs it — `Get-Command pac`, the MCP servers registered with the agent — and never assume a tool is present or absent. Installing and updating them is the harness's `setup-tools` skill's job; Python and the Dataverse tooling are `dv-connect`'s.

## Required

| Tool | What needs it |
| --- | --- |
| PowerShell | The terminal on Windows; `pac` and PCF tooling |
| git | One branch per unit of work |
| .NET SDK | Building and testing plugins and Custom APIs |
| Node.js | Testing and linting web resources and PCF controls; the official skills' hooks and MCP servers |
| Power Platform CLI (`pac`), the Windows installer | Code generation, solution operations, environment access |
| Python | The Dataverse skills' scripts (`scripts/auth.py`) and SDK |
| Azure CLI (`az`) | The model-apps and power-automate skills |

A minimum stated by an official skill (in its README or plugin manifest) is a requirement; read it there rather than copying it here.

`pac` is the Windows installer (winget `Microsoft.PowerAppsCLI`), not the .NET global tool: the installer keeps older versions side by side and updates with `pac install latest`. A second `pac` installed as a .NET tool shadows one or the other on PATH.

`pac` also needs an authentication profile that reaches DEV: the `dv-connect` skill creates it, and `pac org who --environment <dev-url>` confirms which environment a command reaches. `pac pcf init` and `pac modelbuilder` generate project structure and early-bound classes; there is no acceptable manual equivalent. Never hand-write what these commands generate. Plugin projects are the exception: they are not created with `pac plugin init`, but from the `.csproj` in `docs/development/csharp-plugins.md`.

## Per repository

| Tool | When | What it adds |
| --- | --- | --- |
| GitHub CLI (`gh`) | The repository is on GitHub | Pull requests and repository operations from the terminal |
| `az` `azure-devops` extension | The repository is on Azure DevOps | `az repos` and `az devops`: pull requests and repository operations |

`.power-platform/project.json` names the provider (`connections.repository.provider`).

## Recommended

| Tool | What it adds | Without it |
| --- | --- | --- |
| Dataverse MCP server | Reading metadata and records, and writing in DEV, from the agent | The Dataverse CLI, `pac`, or the maker portal |
| `playwright-cli` | Manual checks of PCF controls and web resources in their DEV forms | A manual check in the browser |

`dv-connect` registers the Dataverse MCP server; `setup-tools` installs `playwright-cli`, which suits coding agents because it loads no tool schemas or accessibility trees into context.
