---
name: setup-tools
description: Check and prepare this machine for Power Platform work with the harness — PowerShell, git, .NET SDK, Node.js, pac, Python, az, gh, playwright-cli and its skill, the Dataverse skills and the model-apps, power-automate and Ponytail agent plugins — proposing each install, update or removal for the user to approve. Use when setting up a new machine, when a tool is missing, outdated or installed twice, or when set-power-platform reaches its tools step.
allowed-tools: Bash(pwsh --version), Bash(git --version), Bash(dotnet --version), Bash(dotnet --list-sdks), Bash(dotnet tool list *), Bash(node --version), Bash(npm --version), Bash(npm ls -g *), Bash(npm view *), Bash(pac), Bash(pac help), Bash(python --version), Bash(py --version), Bash(az --version), Bash(az extension list *), Bash(gh --version), Bash(playwright-cli --version), Bash(winget --version), Bash(winget list *), Bash(winget show *), Bash(where *), Bash(npx skills list *), Bash(claude --version), Bash(claude plugin list *), Bash(claude plugin marketplace list *), Bash(copilot --version), Bash(copilot plugin list *), Bash(codex --version), PowerShell(pwsh --version), PowerShell(git --version), PowerShell(dotnet --version), PowerShell(dotnet --list-sdks), PowerShell(dotnet tool list *), PowerShell(node --version), PowerShell(npm --version), PowerShell(npm ls -g *), PowerShell(npm view *), PowerShell(pac), PowerShell(pac help), PowerShell(python --version), PowerShell(py --version), PowerShell(az --version), PowerShell(az extension list *), PowerShell(gh --version), PowerShell(playwright-cli --version), PowerShell(winget --version), PowerShell(winget list *), PowerShell(winget show *), PowerShell(Get-Command *), PowerShell(npx skills list *), PowerShell(claude --version), PowerShell(claude plugin list *), PowerShell(claude plugin marketplace list *), PowerShell(copilot --version), PowerShell(copilot plugin list *), PowerShell(codex --version), Read, Glob, Grep, WebFetch, WebSearch, AskUserQuestion
---

# Set up the tools

This skill owns the machine: CLIs, runtimes, the official skills and the agent plugins. You inspect the machine yourself, decide what is missing, outdated or duplicated, and turn each finding into a **proposal**; you run a proposal only after the user approves it. The repository, connections and authentication belong to other skills: every sign-in (`pac auth`, `az`, `gh`, the `playwright-cli` session) is `connect`'s; Python's packages, the Dataverse MCP server and `.env` are `dv-connect`'s; this skill only reports them.

Talk to the user in the conversation's language. Windows only.

This skill says what the machine needs, not how to install it, on purpose: install methods change faster than this file. For each install, update or removal, look up the method the vendor documents at this moment (its install page or README, the package on winget, npm or the agent's plugin marketplace) and propose that one, citing where you read it.

## What the machine needs

| Tool | Needed for | When |
| --- | --- | --- |
| PowerShell | The terminal; `pac` and PCF tooling | Always. The Windows PowerShell that ships with Windows is enough: report it, never propose installing another |
| git | One branch per unit of work | Always |
| .NET SDK | Building and testing plugins and Custom APIs | Always |
| .NET Framework 4.6.2 or later | Running plugin tests | Always. Windows 10/11 ship it: report it, never propose installing it |
| Node.js | Web resource and PCF tests and lint; the official plugins' hooks and MCP servers; `playwright-cli` | Always |
| Power Platform CLI (`pac`) | Solutions, environment access, code generation | Always |
| Python | The Dataverse skills' scripts and Python SDK: the path to DEV when the tenant restricts the Dataverse MCP server | Always. Its packages are `dv-connect`'s |
| Azure CLI (`az`) | model-apps and power-automate; a signed-in `az` session is a token source for the Dataverse skills' Python SDK, and `dv-connect` lists environments with it when `pac` is not available | Always |
| `az` `azure-devops` extension | `az repos`, `az devops` | Repository on Azure DevOps |
| GitHub CLI (`gh`) | Pull requests and repository operations | Repository on GitHub |
| Playwright CLI (`playwright-cli`, Microsoft) | Checking web resources and PCF controls in DEV forms | Recommended |

When the current folder holds `.power-platform/project.json`, `connections.repository.provider` decides between `gh` and the `azure-devops` extension. Without it, report both as conditional.

| Skills and plugins | Status |
| --- | --- |
| Dataverse skills (`microsoft/Dataverse-skills`) | Mandatory |
| `model-apps`, `power-automate` (marketplace `microsoft/power-platform-skills`) | Mandatory |
| Ponytail (marketplace `DietrichGebert/ponytail`) | Recommended |
| The `playwright-cli` skill, published with the Playwright CLI | Recommended, with `playwright-cli`: it teaches the agent the CLI's commands |
| The other `power-platform-skills` plugins (canvas-apps, pcf, power-pages and the rest) | The user's choice: only when the user asks |

Skills and plugins install per agent. Act on the agent running this skill, and offer the others found on the machine. The harness has not exercised Codex or VS Code agent mode: say so, never claim they work. When an agent runs plugin hooks only after the user trusts them, tell the user.

## 1. Inspect

Read only; change nothing. For each row above, find out whether it is installed, which version and how it was installed, with the tool's own commands and the agents' plugin and skill listings.

Then decide, per tool, whether the installed version is fine. This skill states no versions on purpose: check each one against its official source at this moment — the vendor's release notes or support policy, the latest stable release where the vendor publishes it, and any minimum an official skill states in its README or plugin manifest. Classify each as:

- **ok** — supported and reasonably current.
- **update** — a newer stable release exists. Say which, and where you read it.
- **unsupported** — out of support, or below a minimum an official skill states. Required.
- **missing**.
- **unknown** — you could not read the version or reach the source (no network, say). Say so; never guess.

Also look for:

- **A tool installed twice**, or by two methods (`pac` as both the Windows installer and the .NET global tool, say; the Dataverse skills both as agent skills and as a plugin; two copies in different folders). Two copies of the Dataverse skills can differ in version, and with it in the credential sources their `scripts/auth.py` uses: say which version each copy is. Propose keeping one, say which and why from the vendor's documentation, and removing the rest. A folder no agent registered has no uninstall command: deleting it cannot be undone, so show the path and confirm that proposal on its own.
- **Telemetry**: model-apps and power-automate send usage telemetry by default. State it and offer the opt-out their READMEs document; the user may keep it on.

## 2. Report and propose

Report briefly: a table of tool, version, status and source; the skills and plugins per agent; which agent is you; the findings above.

Then list the proposals as a numbered list: what it does, why, whether it is required or a recommendation, the agent it targets, the exact commands and where that method is documented. Ask which to run: a closed choice, through your structured question tool if you have one, else the numbered list itself with the user answering by number. An answer approves the proposals it names and nothing else.

Run the approved ones in order:

- A proposal that depends on another (a plugin needs its marketplace first, the `playwright-cli` skill needs the CLI) is skipped when that one was declined or failed; say why.
- A command that waits for input (a prompt, a browser sign-in) is the user's to run in their own terminal: give them the command and wait.
- After an install that changes PATH, a new terminal may be needed before the tool is found.
- After a plugin or skill install or update, the agent may need a restart to load it: say so.

Report each command's outcome as it happened, failures included, with the output that explains them.

## 3. Exceptions

When the current folder holds `docs/agents/skill-exceptions.md`: for each exception there, find the installed skill it names and check that its quoted rule still appears in it. An exception whose skill is not installed (Ponytail, a recommendation the user may decline) is not checked: report it as not applicable. A quote that no longer appears is **stale**: the official rule changed. Report it as a bug in this harness, not in the user's machine; until the entry is updated, the official skill applies.

## 4. Close

Inspect again what the approved proposals changed. The skill is done when nothing is proposed, or when every proposal left is one the user declined in this conversation. Close with a short summary: what changed, what the user declined or is still pending, and what stays unverified on this machine.
