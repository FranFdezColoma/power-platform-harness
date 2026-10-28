---
name: setup-tools
description: Check and prepare this machine for Power Platform work with the harness — PowerShell, git, .NET SDK, Node.js, pac, Python, az, gh, the Dataverse skills and the model-apps, power-automate and Ponytail agent plugins — proposing each install, update or removal for the user to approve. Use when setting up a new machine, when a tool is missing, outdated or installed twice, or when set-power-platform reaches its tools step.
allowed-tools: Bash(* --version), Bash(dotnet --list-sdks), Bash(dotnet tool list *), Bash(winget list *), Bash(where *), Bash(pac), Bash(pac help), Bash(npm ls -g *), Bash(npm view *), Bash(npx skills list *), Bash(az extension list *), Bash(claude plugin list *), Bash(claude plugin marketplace list *), Bash(copilot plugin list *), PowerShell(* --version), PowerShell(dotnet --list-sdks), PowerShell(dotnet tool list *), PowerShell(winget list *), PowerShell(Get-Command *), PowerShell(pac), PowerShell(pac help), PowerShell(npm ls -g *), PowerShell(npm view *), PowerShell(npx skills list *), PowerShell(az extension list *), PowerShell(claude plugin list *), PowerShell(claude plugin marketplace list *), PowerShell(copilot plugin list *), Read, Glob, Grep, WebFetch, WebSearch, AskUserQuestion
---

# Set up the tools

This skill owns the machine: CLIs, runtimes, the official skills and the agent plugins. You inspect the machine yourself, decide what is missing, outdated or duplicated, and turn each finding into a **proposal**; you run a proposal only after the user approves it. The repository, connections and authentication belong to other skills: Python's packages, the Dataverse MCP server, `.env` and `pac auth` are `dv-connect`'s, and this skill only reports them.

Talk to the user in the conversation's language. Windows only.

## What the machine needs

| Tool | Needed for | When | Installed with |
| --- | --- | --- | --- |
| PowerShell 7 | The terminal; `pac` and PCF tooling | Always | `winget install --id Microsoft.PowerShell --source winget` |
| git | One branch per unit of work | Always | winget `Git.Git` |
| .NET SDK | Building and testing plugins and Custom APIs | Always | winget, the current LTS SDK |
| .NET Framework 4.6.2 or later | Running plugin tests | Always | Detect only: Windows 10/11 ship it |
| Node.js | Web resource and PCF tests and lint; the official plugins' hooks and MCP servers | Always | winget `OpenJS.NodeJS.LTS` |
| `pac`, the Windows installer | Solutions, environment access, code generation | Always | winget `Microsoft.PowerAppsCLI`; updates with `pac install latest` |
| Python | The Dataverse skills' scripts and SDK | Always | `dv-connect` installs it; only report it |
| Azure CLI (`az`) | model-apps and power-automate | Always | winget `Microsoft.AzureCLI` |
| `az` `azure-devops` extension | `az repos`, `az devops` | Repository on Azure DevOps | `az extension add --name azure-devops` |
| GitHub CLI (`gh`) | Pull requests and repository operations | Repository on GitHub | winget `GitHub.cli` |
| `playwright-cli` | Checking web resources and PCF controls in DEV forms | Recommended | `npm install -g @playwright/cli@latest` |

When the current folder holds `.power-platform/project.json`, `connections.repository.provider` decides between `gh` and the `azure-devops` extension. Without it, report both as conditional.

| Skills and plugins | Status | Installed with |
| --- | --- | --- |
| Dataverse skills (`microsoft/Dataverse-skills`) | Mandatory | `npx skills add microsoft/Dataverse-skills -s "*" -g`. A copy already installed as an agent plugin is accepted: say the npx install is the one the harness expects, and leave it |
| `model-apps`, `power-automate` (marketplace `microsoft/power-platform-skills`) | Mandatory | The agent's plugin CLI |
| Ponytail (marketplace `DietrichGebert/ponytail`) | Mandatory | The agent's plugin CLI |
| The other `power-platform-skills` plugins (canvas-apps, pcf, power-pages and the rest) | The user's choice | The agent's plugin CLI, only when the user asks |

Plugins install through each agent's own CLI: `claude plugin marketplace add <source>` and `claude plugin install <plugin>@<marketplace>`, `copilot plugin install <plugin>@<marketplace>`, `codex plugin add <plugin>@<marketplace>`. Act on the agent running this skill, and offer the others whose CLI is on PATH. The harness has not exercised Codex or VS Code agent mode: say so, never claim they work. Codex runs plugin hooks only once the user trusts them in `/hooks`.

## 1. Inspect

Read only; change nothing. For each row above, find out whether it is installed and which version, with the tool's own commands (`--version`, `dotnet --list-sdks`, `winget list`, `npx skills list -g`, the agents' `plugin list`).

Then decide, per tool, whether the installed version is fine. This skill states no versions on purpose: check each one against its official source at this moment — the vendor's release notes or support policy, the latest release on winget, npm, NuGet or GitHub, and any minimum an official skill states in its README or plugin manifest. Classify each as:

- **ok** — supported and reasonably current.
- **update** — a newer stable release exists. Say which, and where you read it.
- **unsupported** — out of support, or below a minimum an official skill states. Required.
- **missing**.
- **unknown** — you could not read the version or reach the source (no network, say). Say so; never guess.

Also look for:

- **Two `pac` installs**, or `pac` installed as the .NET global tool (`dotnet tool list -g` shows `microsoft.powerapps.cli.tool`). Propose keeping the Windows installer and removing the .NET tool (`dotnet tool uninstall --global Microsoft.PowerApps.CLI.Tool`): the installer keeps versions side by side and switches with `pac use`.
- **Duplicate copies** of the Dataverse skills (npx and a plugin, or two folders). Propose removing the extra one. A folder no agent registered has no uninstall command: deleting it cannot be undone, so show the path and confirm that proposal on its own.
- **Telemetry**: model-apps and power-automate send usage telemetry by default. State it and offer the opt-out their READMEs document; the user may keep it on.

## 2. Report and propose

Report briefly: a table of tool, version, status and source; the skills and plugins per agent; which agent is you; the findings above.

Then list the proposals as a numbered list: what it does, why, whether it is required or a recommendation, the agent it targets, and the exact commands. Ask which to run: a closed choice, through your structured question tool if you have one, else the numbered list itself with the user answering by number. An answer approves the proposals it names and nothing else.

Run the approved ones in order:

- A proposal that depends on another (a plugin needs its marketplace first) is skipped when that one was declined or failed; say why.
- A command that waits for input (a prompt, a browser sign-in) is the user's to run in their own terminal: give them the command and wait.
- After a winget install, a new terminal may be needed before the tool is on PATH.
- After a Claude Code plugin install or update, Claude Code needs a restart to load it.

Report each command's outcome as it happened, failures included, with the output that explains them.

## 3. Exceptions

After installing or updating any official skill or plugin, and when the current folder holds `docs/agents/skill-exceptions.md`: for each exception there, find the installed skill it names and check that its quoted rule still appears in it. A quote that no longer appears is **stale**: the official rule changed. Report it as a bug in this harness, not in the user's machine; until the entry is updated, the official skill applies.

## 4. Close

Inspect again. The skill is done when nothing is proposed, or when every proposal left is one the user declined in this conversation. Close with a short summary: what changed, what the user declined or is still pending, and what stays unverified on this machine.
