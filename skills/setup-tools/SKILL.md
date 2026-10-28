---
name: setup-tools
description: Check and prepare this machine for Power Platform work with the harness — PowerShell, git, .NET SDK, Node.js, pac, az, gh, the Dataverse skills and the model-apps, power-automate and Ponytail agent plugins — proposing each install, update or removal for the user to approve. Use when setting up a new machine, when a tool is missing, outdated or installed twice, or when set-power-platform reaches its tools step.
---

# Set up the tools

This skill owns the machine: CLIs, runtimes, the official skills and the agent plugins. One read-only script reports the machine and derives every action from it as a **proposal**; you run a proposal only after the user approves that proposal. The repository, connections and authentication belong to other skills: Python, its packages, the Dataverse MCP server, `.env` and `pac auth` are `dv-connect`'s, and this skill only reports them.

Talk to the user in the conversation's language.

## The check

`scripts/check-tools.ps1` sits in this skill's folder, next to this file. Run it by its full path:

```
pwsh -NoProfile -File <this skill's folder>/scripts/check-tools.ps1 [-Path <repository>] [-Offline]
```

Without `pwsh`, run the same script and arguments with `powershell -NoProfile -ExecutionPolicy Bypass -File`. Without either, stop and tell the user to install PowerShell 7 (`winget install --id Microsoft.PowerShell --source winget`).

- `-Path .` when the current folder holds `.power-platform/project.json`: its repository provider decides whether `gh` or the az `azure-devops` extension is required. Without it, both are reported as conditional.
- `-Offline` when the user says there is no network: update detection is skipped, everything else is checked.

The script takes 10 to 20 seconds, prints one JSON document and changes nothing: it reads tools, files and, unless `-Offline`, GitHub.

## 1. Report

Report from the JSON, briefly, in this order:

- `toolchain.requirements` as a table: tool, version, minimum, status. Name each minimum's `minimumSource`: `documented` (by the plugin in `documented[].by`) or `harness-policy`. Put a `warning` next to its status. A `unknown` status means the version could not be read: ask the user to confirm it.
- `toolchain.repository`: what the provider requires; a `conditional` entry is needed only for that kind of repository.
- `pac.installs` when there is more than one, or when the install is the .NET global tool: the harness uses the Windows installer, which keeps versions side by side, updates with `pac install latest` and switches with `pac use`. How an `msi` install is recognised is stated in `notes`.
- `agents`: which agents are on this machine. An agent whose `plugins` is `unverified` gets its `note` stated as is: the harness has not exercised it, so never claim it works. Say which agent is you.
- `dataverseSkills.status` and its copies. `plugin-only` is accepted: say the npx install is the one the harness expects, and leave it.
- `telemetry`: model-apps and power-automate send usage telemetry by default. State each plugin's `state` and offer the opt-out; the plugins' own READMEs list what is collected.
- `skillExceptions`: an exception whose status is `stale` is a bug in this harness, not in the user's machine: the official rule it quotes changed, and `docs/agents/skill-exceptions.md` and `scripts/skill-exceptions.json` need updating. `mixed` means an old copy disagrees with the current one; removing the duplicate resolves it.
- `notes`, each in one line.

## 2. Propose

List the `proposals` as a numbered list: what it does, why (`reason`), its `severity`, the agent it targets, and the exact `commands`. Then ask which to run: a closed choice, through your structured question tool if you have one, else the numbered list itself with the user answering by number. An answer approves the specific proposals it names and nothing else.

Run the approved ones in list order:

- `agent` names the agent the proposal installs into. Proposals for you act on the agent running this skill; those for another agent run through that agent's CLI and are offered the same way.
- `dependsOn` names a proposal that must succeed first. When that one was declined or failed, skip this one and say why.
- `delete-folder` removes a copy no agent registered, so no uninstall command exists for it and the deletion cannot be undone: show the path and confirm that proposal on its own before running it.
- `configure` with severity `choice` is the telemetry opt-out. The first command is typed by the user in their agent; the second sets the documented environment variable for this Windows user, and it reaches agents started afterwards. A user who keeps telemetry on can record that with `/<plugin>:telemetry on`, which ends the proposal.
- A command that waits for input (a prompt, a browser sign-in) is the user's to run in their own terminal: give them the command and wait.
- After a winget install, a new terminal may be needed before the tool is on PATH.
- After a Claude Code plugin install or update, Claude Code needs a restart to load it.

The other power-platform-skills plugins (canvas-apps, pcf, power-pages and the rest of that marketplace) are the user's choice: when the user asks for one, install it the same way, through the agent's `plugin install`, after the same approval.

Report each command's outcome as it happened, failures included, with the output that explains them.

## 3. Re-run

Run the check again with the same arguments. The skill is done when `proposals` is empty, or when every proposal left is one the user declined in this conversation. If any skills or plugins were installed or updated, read `skillExceptions` again and report a `stale` one as above.

Close with a short summary: what changed, what the user declined or is still pending, and what stays unverified on this machine.
