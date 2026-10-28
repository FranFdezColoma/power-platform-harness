# Toolchain

The tools this repository expects on a developer machine, and what each one is for. These versions describe the machine, not the project: the target frameworks and package versions the code uses are the ones stated in `docs/development/*.md`.

Tool availability belongs to the machine, not to the repository. Check what is available when a task needs it — `Get-Command pac`, the MCP servers registered with the agent — and never assume a tool is present or absent. Installing and updating them is the harness's `setup-tools` skill's job; Python and the Dataverse tooling are `dv-connect`'s.

## Required

| Tool | Minimum | Preferred | What needs it |
| --- | --- | --- | --- |
| PowerShell | 5.1 | 7 | The harness scripts; `pac` and PCF tooling are tested against 7 |
| git | any | latest | One branch per unit of work |
| .NET SDK | 8 | 10 | Building and testing plugins and Custom APIs |
| Node.js | 22.13 | 24 | Testing and linting web resources and PCF controls; the official skills' hooks and MCP servers |
| Power Platform CLI (`pac`), the Windows installer | above 2.10.0 | latest | Code generation, solution operations, environment access |
| Python | any | latest | The Dataverse skills' scripts (`scripts/auth.py`) and SDK |
| Azure CLI (`az`) | any | latest | The model-apps and power-automate skills |

Where the minimum comes from:

- **Harness policy** — a stable, non-obsolete release: PowerShell 5.1, .NET SDK 8, Node.js 22.13. The test and lint tooling the standards pin rejects older Node lines and the odd-numbered 23 and 25.
- **Documented by an official skill** — `pac` above 2.10.0 (model-apps).
- **any** — no version is stated; the latest is preferred.

`pac` is the Windows installer (winget `Microsoft.PowerAppsCLI`), not the .NET global tool: the installer keeps older versions side by side and updates with `pac install latest`. A second `pac` installed as a .NET tool shadows one or the other on PATH.

`scripts/new-feature.ps1` runs on either PowerShell and needs git and, for the feature solution checks, `pac`.

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
