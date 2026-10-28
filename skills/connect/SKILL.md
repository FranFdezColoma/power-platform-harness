---
name: connect
description: Sign in to everything a Power Platform harness project needs and check it against .power-platform/project.json — a pac profile that reaches the DEV environment, the az session in the project's tenant, the repository (gh for GitHub, the az session for Azure DevOps, in its own tenant when it differs), the playwright-cli session signed in to DEV, the Dataverse MCP server or, when the tenant restricts it, the az session the Dataverse skills' Python SDK takes its token from, and dv-connect's .env — without changing any default another project relies on. Use before or after setup-project, when switching machines, when a command reaches the wrong environment, or when set-power-platform reaches its connect steps.
allowed-tools: Bash(pac auth list*), Bash(pac auth who*), Bash(pac org who *), Bash(pac org list*), Bash(pac org fetch *), Bash(git remote *), Bash(gh auth status*), Bash(gh repo view *), Bash(az account show*), Bash(az extension list *), Bash(az devops project list *), Bash(playwright-cli --version), Bash(python scripts/auth.py --diagnose), PowerShell(pac auth list*), PowerShell(pac auth who*), PowerShell(pac org who *), PowerShell(pac org list*), PowerShell(pac org fetch *), PowerShell(git remote *), PowerShell(gh auth status*), PowerShell(gh repo view *), PowerShell(az account show*), PowerShell(az extension list *), PowerShell(az devops project list *), PowerShell(playwright-cli --version), PowerShell(python scripts/auth.py --diagnose), Read, Edit, Glob, Grep, AskUserQuestion
---

# Connect the project

This skill owns the project's sign-ins and connections. You find out what each one should reach, check whether the live session already reaches it, and when it does not, give the user the sign-in command and verify it afterwards. The Dataverse MCP server, `.env` and Python's packages are `dv-connect`'s: hand them to it instead of doing them yourself.

Talk to the user in the conversation's language.

## Two passes

- **Before the repository is set up** — no `.power-platform/project.json` in the current folder. Do the sign-ins (sections 1 to 3) and keep the values you resolved in the conversation: `setup-project` writes them into `project.json`. Do not hand anything to `dv-connect` yet: it lays out folders of its own, and the harness lays the repository out first (exception E2 in `docs/agents/skill-exceptions.md`). Report the Dataverse MCP server and `.env` as pending for the next pass.
- **With `project.json`** — it says what the project expects. Do every section, and record the connections it is still missing (section 6).

Without `pac`, the Dataverse sign-in is pending: point at `setup-tools` and continue with the rest.

## Rules

- Never change a default another project relies on: no `pac auth select`, no `az account set`, no `az devops configure --defaults`. Pass `--environment <devUrl>` to every `pac` command, and `--org` and `--project` to every `az devops` and `az repos` command.
- A sign-in that opens a browser or waits for input is the user's to run in their own terminal: give them the exact command, wait, then verify it with the check the section names.
- `az login` changes the active `az` account for every project on the machine. Say so before giving it.
- Use the sign-ins the tools offer, never a personal access token or a secret: a token kept on the machine is a credential that expires and leaks.
- The only file this skill writes is `.power-platform/project.json`, and only its `connections` section, after the user confirms each value. It never holds a secret.
- A value you could not confirm stays `null`; never guess one.

## 1. Dataverse (`pac`)

1. **DEV url.** Take `connections.dataverse.devUrl`, or the url passed to this skill. When there is none, ask for the DEV environment url in a plain message (it is a free value, not a closed choice) and wait.
2. **Profile.** When `pac auth list` has a profile with which `pac org who --environment <devUrl>` succeeds, reuse it. Otherwise give the user `pac auth create --name <profile> --environment <devUrl>`. `<profile>` is the project name (`identity.projectName`, or the one passed to this skill); before the project has one, the subdomain of the DEV url. A named profile per project keeps them apart on a machine that works for several. Verify with `pac org who --environment <devUrl>`.
3. **Check it.** The url `pac` reached must be the DEV url. Its friendly name and url must not look like production or test (`prod`, `prd`, `live`, `test`, `qa`, `uat`, `stag`, `preprod`): the harness writes in DEV only. If it does, say so and do not record it.
4. **Tenant.** Take `tenantId` from `pac org who`.

## 2. Azure (`az`)

The model-apps and power-automate skills, and the Dataverse skills' Python SDK when the tenant restricts the MCP server, use the `az` session.

- `az account show` must show a signed-in account whose `tenantId` is the Dataverse tenant. When it shows none, or another tenant, give the user `az login --tenant <tenantId>` and wait. Verify with `az account show`.

## 3. Repository

1. **Provider and url.** Take `connections.repository`, or what was passed to this skill. Otherwise read `git remote get-url origin`: `github.com` is `github`; `dev.azure.com` or `visualstudio.com` is `azure-devops`. Propose it and confirm it. With no remote, ask for the provider (a closed choice: `github` or `azure-devops`) and leave the url `null`. A remote that disagrees with the recorded provider is a conflict: report it, do not resolve it.
2. **`github`.** `gh auth status` must show a signed-in account; when it does not, give the user `gh auth login`. Then `gh repo view <url>` must reach the repository.
3. **`azure-devops`.** `az extension list` must include `azure-devops` (`setup-tools` installs it). The repository is reached through the `az` session: `az devops project list --org <organization url>` must succeed.
   - When it fails while `az` is signed in to the Dataverse tenant, the organization is likely in another tenant — common when the repository is hosted by another company than the environment. Ask for the organization's tenant id (a free value), and give the user `az login --tenant <that tenant>`. Explain that `az` has one active account: whichever tenant the user signed in to last decides whether DEV's `az` path or the repository answers, and they switch by signing in again. Record that tenant as `connections.repository.tenantId`; it is `null` when it is the Dataverse tenant or the provider is `github`.

## 4. `playwright-cli` session

Second pass only, and only when `playwright-cli` is installed (`setup-tools` recommends it): otherwise report it as not applicable.

The session is named `connections.playwright.session`. Look up how the installed `playwright-cli` and its skill keep a named, persistent browser profile, and use that one: the profile holds the DEV sign-in, so it lives in the CLI's per-user location, never in the repository. Open the session headed at the DEV url and let the user sign in in that window; then check that the page shows the environment, not a sign-in page. A session already signed in is reused.

## 5. Dataverse MCP server, Python SDK and `.env`

Second pass only.

The Dataverse skills reach DEV through the MCP server or through their Python SDK (`scripts/auth.py`). The MCP server is often restricted at tenant level: admin consent for its app is refused, or its client is not on the environment's allowlist. Then the SDK is the path, and `scripts/auth.py` can take its token from the `az` session of section 2.

- **MCP server.** Check your own tools for a Dataverse MCP server. If there is none, ask the user whether the tenant restricts it. If it does not, or they do not know, recommend `dv-connect`: tell it that the `pac` profile of section 1 exists, and ask it to register the server with `local` scope (this user, this project, not versioned). If it does, or `dv-connect`'s validation already failed on consent or the allowlist, do not recommend registering it again: report it as restricted by the tenant, not as pending, and check the SDK path below.
- **SDK path.** When `scripts/auth.py` exists and offers `--diagnose`, run `python scripts/auth.py --diagnose`: it reports which credential source the next call will use, without prompting. Whether `az` is one of those sources depends on the installed version of the Dataverse skills: when it is not listed, say so rather than assume it.
- **Helper scripts.** `dv-connect` writes `scripts/auth.py` and `scripts/enable-mcp-client.py`. When they exist and are not committed, recommend committing them: a change to authentication code is reviewed like any other.
- **`.env` drift.** When `.env` exists, compare `DATAVERSE_URL`, `TENANT_ID` and `PUBLISHER_PREFIX` with `connections.dataverse.devUrl`, `connections.dataverse.tenantId` and `identity.publisherPrefix`. Report every difference and hand the fix to `dv-connect`; never edit `.env` yourself. `SOLUTION_NAME` changes per branch and is not compared. Never print a secret it holds.

## 6. Record

With `project.json`: propose the values it is missing or that differ — `dataverse.devUrl` and `dataverse.tenantId`, `repository.url` and `repository.tenantId` — and write them once the user confirms. Without it: list the values you resolved, for `setup-project` to write.

## 7. Report

One table: connection, what is expected, what the live session shows, status. The connections are the `pac` profile and DEV, the `az` session, the repository, the `playwright-cli` session and the Dataverse MCP server; the MCP server's status is one of registered, missing or restricted by the tenant, and with it missing or restricted the table also shows the SDK path. Then the pending actions, each with who does it (the user, `dv-connect`, the next pass) and the exact command, and what you wrote to `project.json`.
