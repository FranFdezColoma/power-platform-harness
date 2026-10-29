---
name: setup-tools
description: Check and prepare this Windows machine for Power Platform work with the harness — runtimes, CLIs, the official Power Platform skills and agent plugins — proposing each install, update or removal for the user to approve. Use when setting up a new machine, when a tool is missing, outdated or installed twice, or when set-power-platform reaches its tools step.
allowed-tools: Bash(git --version), Bash(git remote get-url *), Bash(dotnet --list-sdks), Bash(dotnet tool list *), Bash(node --version), Bash(npm --version), Bash(npm ls -g*), Bash(npm outdated -g*), Bash(npm view *), Bash(pac), Bash(python --version), Bash(py --version), Bash(az --version), Bash(az extension list*), Bash(gh --version), Bash(playwright-cli --version), Bash(openspec --version), Bash(winget --version), Bash(winget list*), Bash(winget show *), Bash(winget upgrade), Bash(where *), Bash(claude --version), Bash(claude plugin list*), Bash(claude plugin marketplace list*), Bash(copilot --version), Bash(copilot plugin list*), Bash(codex --version), PowerShell(git --version), PowerShell(git remote get-url *), PowerShell(dotnet --list-sdks), PowerShell(dotnet tool list *), PowerShell(node --version), PowerShell(npm --version), PowerShell(npm ls -g*), PowerShell(npm outdated -g*), PowerShell(npm view *), PowerShell(pac), PowerShell(python --version), PowerShell(py --version), PowerShell(az --version), PowerShell(az extension list*), PowerShell(gh --version), PowerShell(playwright-cli --version), PowerShell(openspec --version), PowerShell(winget --version), PowerShell(winget list*), PowerShell(winget show *), PowerShell(winget upgrade), PowerShell(Get-Command *), PowerShell(claude --version), PowerShell(claude plugin list*), PowerShell(claude plugin marketplace list*), PowerShell(copilot --version), PowerShell(copilot plugin list*), PowerShell(codex --version), Read, Glob, Grep, WebFetch, WebSearch, AskUserQuestion
---

# Set up the tools

This skill owns the machine: CLIs, runtimes, the official skills and the agent plugins. You inspect the machine yourself, decide what is missing, outdated or duplicated, and turn each finding into a **proposal**; you run a proposal only after the user approves it. The repository, connections and authentication belong to other skills: every sign-in (`pac auth`, `az`, `gh`, the `playwright-cli` session) is `connect`'s; Python's packages, the Dataverse MCP server and `.env` are `dv-connect`'s; this skill only reports them.

Talk to the user in the conversation's language. Windows only.

This skill says what the machine needs, not how to install it, on purpose: install methods change faster than this file. For each install, update or removal, look up the method the vendor documents at this moment (its install page or README, the package on winget, npm or the agent's plugin marketplace) and propose that one, citing where you read it. Corporate machines often lack admin rights: where the vendor offers a per-user install (`winget --scope user`, a user installer), prefer it, and say when a proposal needs elevation.

## What the machine needs

| Tool | Needed for | When |
| --- | --- | --- |
| git | One branch per unit of work; the agents' plugin marketplaces | Always |
| .NET SDK | Building and testing plugins and Custom APIs | Always. 10 or later for a new project (its solution file is `.slnx`, which older SDKs cannot read): the one minimum this harness states. When the current folder has a `global.json`, the SDK it selects is what the project needs instead |
| Node.js | Web resource and PCF tests and lint; the official plugins' hooks and MCP servers; `openspec` and `playwright-cli` | Always |
| Power Platform CLI (`pac`) | Solutions, environment access, code generation | Always |
| Python | The Dataverse skills' scripts and Python SDK: the path to DEV when the tenant restricts the Dataverse MCP server | Always. Its packages are `dv-connect`'s |
| Azure CLI (`az`) | model-apps and power-automate; a signed-in `az` session is a token source for the Dataverse skills' Python SDK, and `dv-connect` lists environments with it when `pac` is not available | Always |
| OpenSpec CLI (`openspec`, npm `@fission-ai/openspec`) | The spec workflow: `setup-project` runs `openspec init`, and the `/opsx` skills it generates call the CLI | Always |
| `az` `azure-devops` extension | `az repos`, `az devops` | Repository on Azure DevOps |
| GitHub CLI (`gh`) | Pull requests and repository operations | Repository on GitHub |
| Playwright CLI (`playwright-cli`, Microsoft) | Checking web resources and PCF controls in DEV forms | Recommended |

Windows PowerShell 5.1 and .NET Framework 4.8 (plugin tests) ship with Windows 10/11: do not check them and never propose installing them or PowerShell 7.

The repository provider decides between `gh` and the `azure-devops` extension. Take it, in this order, from what `set-power-platform` passed on, from `connections.repository.provider` in `.power-platform/project.json`, or from `git remote get-url origin` (`github.com` is GitHub; `dev.azure.com` or `visualstudio.com` is Azure DevOps). When none of them answers, ask the user: GitHub, Azure DevOps, or not decided yet; with the last, report both as conditional.

| Skills and plugins | Status |
| --- | --- |
| Dataverse skills (`microsoft/Dataverse-skills`) | Mandatory |
| `model-apps`, `power-automate` (marketplace `microsoft/power-platform-skills`) | Mandatory |
| Ponytail (marketplace `DietrichGebert/ponytail`) | Recommended |
| The `playwright-cli` skill, published with the Playwright CLI | Recommended, with `playwright-cli`: it teaches the agent the CLI's commands |
| The other `power-platform-skills` plugins (canvas-apps, pcf, power-pages and the rest) | The user's choice: only when the user asks |

The OpenSpec skills (`openspec-*`, `/opsx`) are not installed here: `openspec init` writes them into the repository. The Microsoft Learn MCP server, which solutioning uses as its reference, comes with `power-automate`: report it as covered by that plugin, never propose installing it separately; without it the agent falls back to web search.

Skills and plugins install per agent. Act on the agent running this skill, and offer the others found on the machine. List plugins with each agent's plugin commands, and skills by reading the skill folders the agent documents (user level and the current repository). The harness has not exercised Codex or VS Code agent mode: say so, never claim they work. When an agent runs plugin hooks only after the user trusts them, tell the user.

## 1. Inspect

Read only; change nothing. For each row above, find out whether it is installed, which version and how it was installed, with the tool's own commands and the agents' plugin and skill listings. On Windows, a `python` that resolves (`where python`) only to `WindowsApps` is the Microsoft Store alias, not an install: count it as missing.

Then decide, per tool, whether the installed version is fine. Start with the package managers' own view, one call each: `winget upgrade` lists the newer releases of what winget installed, `npm outdated -g` of the global npm packages. Go to the vendor's site only for what they do not cover, and for support status. This skill states no versions on purpose, except the .NET SDK floor in the table above; the reference is:

- Node.js: the active LTS line, not Current.
- Python: the newest release with support that the Dataverse skills' dependencies accept, not simply the newest.
- Anything else: the vendor's latest stable release and its support policy.
- Any minimum an official skill states in its README or plugin manifest, and the `engines` field of the npm packages above (`npm view <package> engines`).

Classify each as:

- **ok** — supported and reasonably current, including a patch or minor release behind.
- **update** — a newer major release, or a release the vendor marks as a security fix. Say which, and where you read it.
- **unsupported** — out of support, or below a minimum stated above. Required.
- **missing**.
- **unknown** — you could not read the version or reach the source (no network, say). Say so; never guess.

Also look for:

- **A tool installed twice**, or by two methods (`pac` as the Windows installer, the .NET global tool and the copy the Power Platform Tools VS Code extension puts on PATH, say; the Dataverse skills both as agent skills and as a plugin; two copies in different folders). Two copies of the Dataverse skills can differ in version, and with it in the credential sources their `scripts/auth.py` uses: say which version each copy is. Propose keeping one, say which and why from the vendor's documentation, and removing the rest. A folder no agent registered has no uninstall command: deleting it cannot be undone, so show the path and confirm that proposal on its own.
- **Telemetry**: model-apps and power-automate each ship a `telemetry` skill that reports and changes their usage telemetry. Use it to read the current state; propose the opt-out only where telemetry is on. The user may keep it on.

## 2. Report and propose

Report briefly: a table of tool, version, status and source; the skills and plugins per agent; which agent is you; the findings above.

Then list the proposals as a numbered list: what it does, why, whether it is required or a recommendation, the agent it targets, the exact commands and where that method is documented. Releases classified **ok** but behind go together into one optional proposal, "update the rest", never one each. Ask which to run: a closed choice, through your structured question tool if you have one, else the numbered list itself with the user answering by number. An answer approves the proposals it names and nothing else.

Run the approved ones in this order: runtimes (.NET SDK, Node.js, Python) and git first, then the CLIs (`pac`, `az` and its extension, `gh`, `openspec`, `playwright-cli`), then the skills and plugins, each marketplace before its plugins.

- A proposal that depends on another (an npm package needs Node.js, a plugin needs git and its marketplace, the `playwright-cli` skill needs the CLI) is skipped when that one was declined or failed; say why.
- A tool you just installed is not on your own process's PATH: your commands inherit the PATH your agent started with. Before using it in a later proposal, reload PATH inside that same command (in PowerShell, `$env:Path = [Environment]::GetEnvironmentVariable('Path','Machine') + ';' + [Environment]::GetEnvironmentVariable('Path','User')`), or call it by its full path. If it is still not found, stop the dependent proposals and ask the user to restart the agent and run this skill again.
- A command that waits for input (a prompt, a UAC elevation, a browser sign-in) is the user's to run in their own terminal: give them the command and wait.
- After a plugin or skill install or update, the agent may need a restart to load it: say so.

Report each command's outcome as it happened, failures included, with the output that explains them.

## 3. Close

Inspect again what the approved proposals changed. The skill is done when nothing is proposed, or when every proposal left is one the user declined in this conversation. Close with a short summary: what changed, what the user declined or is still pending, and what stays unverified on this machine.
