---
name: connect
description: Check and complete the connections a Power Platform harness project expects — pac against the DEV environment, the tenant, the repository and its provider, the Dataverse MCP server and dv-connect's .env — against .power-platform/project.json, without changing any default another project relies on. Use after setup-project, when switching machines, when a command reaches the wrong environment, or when set-power-platform reaches its connect step.
allowed-tools: Bash(pac auth list*), Bash(pac auth who*), Bash(pac org who *), Bash(pac org list*), Bash(pac org fetch *), Bash(git remote *), Bash(gh auth status*), Bash(az account show*), Bash(az extension list *), PowerShell(pac auth list*), PowerShell(pac auth who*), PowerShell(pac org who *), PowerShell(pac org list*), PowerShell(pac org fetch *), PowerShell(git remote *), PowerShell(gh auth status*), PowerShell(az account show*), PowerShell(az extension list *), Read, Edit, Glob, Grep, AskUserQuestion
---

# Connect the project

This skill owns the project's connections. `.power-platform/project.json` says what the project expects; you check that the live sessions point there, fill the `connections` it is still missing, and report the rest. Creating authentication, the Dataverse MCP server and `.env` are `dv-connect`'s: when one is missing or wrong, hand it to `dv-connect` instead of doing it yourself.

Talk to the user in the conversation's language.

Without `.power-platform/project.json` in the current folder, stop: the `setup-project` skill writes it. Without `pac`, stop and point at `setup-tools`.

## Rules

- Never change a default another project relies on: no `pac auth select`, no `az account set`, no `az devops configure --defaults`. Pass `--environment <devUrl>` to every `pac` command instead.
- The only file this skill writes is `.power-platform/project.json`, and only its `connections` section, after the user confirms each value. It never holds a secret.
- A value you could not confirm stays `null`; never guess one.

## 1. Dataverse

1. **DEV url.** Read `connections.dataverse.devUrl`. When it is `null`, ask for the DEV environment url in a plain message (it is a free value, not a closed choice) and wait.
2. **Reach it.** Run `pac org who --environment <devUrl>`. With no authentication profile at all (`pac auth list` is empty), or when the call fails to authenticate, recommend running `dv-connect`, which creates the profile; continue with the rest and report this as pending.
3. **Check it.** The url `pac` reached must be the one `project.json` names. Its friendly name and url must not look like production or test (`prod`, `prd`, `live`, `test`, `qa`, `uat`, `stag`, `preprod`): the harness writes in DEV only. If it does, say so and do not record it.
4. **Record it.** Propose `devUrl` and `tenantId` (from `pac org who`) for `project.json` and write them once the user confirms.

## 2. Repository

- Read `git remote get-url origin`. Propose it as `connections.repository.url`. If it disagrees with `connections.repository.provider` (`github.com` is `github`; `dev.azure.com` or `visualstudio.com` is `azure-devops`), report the conflict instead of resolving it.
- `github`: `gh auth status` must show an account that can reach the repository.
- `azure-devops`: `az account show` must show a signed-in account, and `az extension list` must include `azure-devops`. Commands against the repository pass `--org` and `--project` rather than relying on defaults.
- A missing sign-in is the user's to run in their own terminal (`gh auth login`, `az login`): give them the command and wait.

## 3. Dataverse MCP server and `.env`

- **MCP server.** Check your own tools for a Dataverse MCP server. If there is none, recommend `dv-connect`, and ask it to register the server with `local` scope (this user, this project, not versioned).
- **Helper scripts.** `dv-connect` writes `scripts/auth.py` and `scripts/enable-mcp-client.py`. When they exist and are not committed, recommend committing them: a change to authentication code is reviewed like any other.
- **`.env` drift.** When `.env` exists, compare `DATAVERSE_URL`, `TENANT_ID` and `PUBLISHER_PREFIX` with `connections.dataverse.devUrl`, `connections.dataverse.tenantId` and `identity.publisherPrefix`. Report every difference and hand the fix to `dv-connect`; never edit `.env` yourself. `SOLUTION_NAME` changes per branch and is not compared. Never print a secret it holds.

## 4. Report

One table: connection, what `project.json` expects, what the live session shows, status. Then the pending actions, each with who does it (the user, `dv-connect`) and the exact command, and what you wrote to `project.json`.
