# Toolchain

The tools this repository expects on a developer machine, and what each one is for. These versions describe the machine, not the project: the target frameworks and package versions the code uses are the ones stated in `docs/development/*.md`.

Tool availability belongs to the machine, not to the repository. Check what is available when a task needs it — `Get-Command pac`, the MCP servers registered with the agent — and never assume a tool is present or absent.

## Required

| Tool | Minimum | Preferred | What needs it |
| --- | --- | --- | --- |
| PowerShell | 5.1 | 7 | The harness scripts; `pac` and PCF tooling are tested against 7 |
| git | any | latest | One branch per unit of work |
| .NET SDK | 8 | 10 | Building and testing plugins and Custom APIs; installing `pac` |
| Node.js | 20 | 24 | Testing and linting web resources and PCF controls |
| Power Platform CLI (`pac`) | any | latest | Code generation, solution operations, environment access |

Install:

- PowerShell 7: `winget install --id Microsoft.PowerShell --source winget`
- git: `winget install --id Git.Git --source winget`
- .NET SDK 10: `winget install --id Microsoft.DotNet.SDK.10 --source winget`
- Node.js 24: `winget install --id OpenJS.NodeJS.LTS --source winget`, or a version manager such as `nvm`
- `pac`: `dotnet tool install --global Microsoft.PowerApps.CLI.Tool`

`pac` also needs an authentication profile against DEV: `pac auth create --environment <dev-url>`, then `pac org who` to confirm which environment it points at. `pac pcf init`, `pac plugin init --skip-signing` and `pac modelbuilder` generate project structure and early-bound classes; there is no acceptable manual equivalent. Never hand-write what these commands generate.

## Recommended

| Tool | What it adds | Without it |
| --- | --- | --- |
| Dataverse MCP server | Reading metadata and records, and writing in DEV, from the agent | `pac`, or the maker portal |
| Playwright (`playwright-cli`, or the Playwright MCP server) | Manual checks of PCF controls and web resources in their DEV forms | A manual check in the browser |

Setup:

- **Dataverse MCP server** — either register the remote endpoint (an Entra app registration), or install the local proxy (`dotnet tool install --global Microsoft.PowerPlatform.Dataverse.MCP`) and register it with the agent. The feature must also be enabled on the environment: Power Platform admin center > environment > Settings > Product > Features > Dataverse Model Context Protocol. [Documentation](https://learn.microsoft.com/power-apps/maker/data-platform/data-platform-mcp).
- **Playwright** — prefer `playwright-cli` for coding agents, since it loads no tool schemas or accessibility trees into context: `npm install -g @playwright/cli@latest`. The MCP alternative is `claude mcp add playwright npx @playwright/mcp@latest`.

The GitHub CLI (`gh`) is optional: it speeds up pull requests, and the web UI does the same.
