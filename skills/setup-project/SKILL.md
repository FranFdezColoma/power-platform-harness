---
name: setup-project
description: Install or update the Power Platform / Dynamics 365 CE harness in a repository — agent instructions, OpenSpec with its gates, development and solutioning standards, permission rules — and, in an empty folder, the starting code. Reads publisher, prefix, core solution and stack from an existing project instead of asking. Use when set-power-platform reaches its project step, to adopt the harness into a repository, or to bring its harness files up to date.
allowed-tools: Bash(git init *), Bash(git status*), Bash(git remote *), Bash(git log *), Bash(git switch -c *), Bash(git add *), Bash(git commit *), Bash(git diff*), Bash(openspec *), Bash(pac auth list*), Bash(pac org who *), Bash(pac solution list *), Bash(pac org fetch *), Bash(dotnet --list-sdks), Bash(dotnet build *), Bash(dotnet new *), Bash(dotnet sln *), Bash(pac plugin init*), Bash(npm test*), Bash(powershell -NoProfile -ExecutionPolicy Bypass -File *new-folders.ps1 *), Bash(npm run lint*), PowerShell(git init *), PowerShell(git status*), PowerShell(git remote *), PowerShell(git log *), PowerShell(git switch -c *), PowerShell(git add *), PowerShell(git commit *), PowerShell(git diff*), PowerShell(openspec *), PowerShell(pac auth list*), PowerShell(pac org who *), PowerShell(pac solution list *), PowerShell(pac org fetch *), PowerShell(dotnet --list-sdks), PowerShell(dotnet build *), PowerShell(dotnet new *), PowerShell(dotnet sln *), PowerShell(pac plugin init*), PowerShell(npm test*), PowerShell(npm run lint*), PowerShell(powershell -NoProfile -ExecutionPolicy Bypass -File *new-folders.ps1 *), Read, Write, Edit, Glob, Grep, AskUserQuestion
---

# Set up the project

This skill owns the repository. It writes the harness files from `templates/`, next to this file, into the current folder.

The templates are the product. Copy them; never write, paraphrase or improve their content yourself. The shipped templates are in English and stay English whatever the conversation language.

Talk to the user in the conversation's language.

## Modes

Step 1 decides the mode. Then follow only its row:

| Mode | Steps | Also read |
| --- | --- | --- |
| **Empty folder** — every template, then the starting code | 1, 2, 4, 6, 7, 8 | `references/existing-project.md`, step 4 only, for a README or `.gitignore` already there |
| **Existing project** — only what is missing; the project's stack wins; no code is created | 1, 2, 3, 4, 5, 7, 8 | `references/existing-project.md` (steps 3 and 5, kept files) |
| **Harness already present** — what is missing, and a proposal for each file whose template changed | 1, 2, 4, 7, 8 | `references/harness-present.md` (comparing files with their templates) |

## Asking the user

- **Free values** (project name, publisher, prefix, core solution, description): ask in a plain message as a numbered list, then stop and wait. A structured question tool needs predefined options, and a free value has none.
- **Closed choices** (the repository provider, one of several publishers found, the go-ahead, committing): your structured question tool if you have one, else a numbered list the user answers by number.

Never invent a value. Never derive one silently from the folder name. A wrong publisher prefix cannot be undone once components exist.

Show the user every diff to an existing file before writing it. If an existing file contradicts a harness rule, report the conflict instead of resolving it silently.

## 1. Inspect

Read the folder before asking anything; write nothing.

- **Mode.** Empty (nothing but `.git`, a README, a licence, a `.gitignore` or editor and agent settings such as `.vscode/`, `.idea/` or `.claude/settings.local.json`), existing project, or harness already present (`.power-platform/project.json`, `docs/agents/development-standards.md`).
- **OpenSpec.** Whether `openspec/config.yaml` exists, and whether `openspec --version` answers.
- **Identity evidence.** A committed `Other/Solution.xml` gives the solution unique name, the publisher unique name and its customization prefix. The `.csproj` files' `RootNamespace` gives the project name; a dotted root namespace (`Acme.Crm`) is worth noting. Web resource names and folders (`<prefix>_/...`) hint at the prefix. The README may describe the project. `git remote get-url origin` gives the provider.
- **Environment, when `pac` reaches one.** The DEV url is the one `connect` resolved, or `connections.dataverse.devUrl`. `pac solution list --environment <url>` lists the unmanaged solutions; the publishers come from `pac org fetch` over the `publisher` table (unique name, prefix, whether it is a default publisher). Branch solutions named `feature_*`, `fix_*` or `chore_*` are not the core solution. Skip this when `pac` is not connected (`connect` has not run, or its Dataverse sign-in is pending); the values are asked instead.
- **Stack, existing project only.** See `references/existing-project.md`.

## 2. Values

| Value | Token | What it is | Rules |
| --- | --- | --- | --- |
| Project name | `{{project_name}}` | Short project name. Also the root .NET namespace, the JavaScript form API namespace and the WebResources project name. Never ask for a namespace separately | Starts with a letter, letters and digits only |
| Publisher unique name | `{{publisher_unique_name}}` | Dataverse publisher **unique** name, not its display name | Letters, digits and underscores |
| Publisher prefix | `{{publisher_prefix}}` | Customization prefix, carried by every component | 2 to 8 lowercase letters and digits, starts with a letter, does not start with `mscrm`. **Permanent**: say so before accepting it |
| Core solution | `{{core_solution}}` | Unique name of the core unmanaged solution in DEV, or `none` | Letters, digits and underscores, no publisher prefix. Optional: `none` when the project has none |
| Description | `{{project_description}}` | One or two sentences on what the project delivers | Free text |
| Artifact language | `{{artifact_language}}` | The project language: OpenSpec artifacts and everything else that is not code | A closed choice: Spanish, English, French, German, or another the user names. Default: the conversation's language |
| Repository provider | `{{repository_provider}}` | Where the repository is hosted | `github` or `azure-devops`. Propose it from the remote and confirm it; with no remote, ask |
| — | `{{repository_cli}}` | Derived, never asked | `gh` for `github`, `az repos` for `azure-devops` |

Show the values as a table with value, source and confidence — **read** (from a committed `Solution.xml` or the environment), **inferred** (a namespace, file names, a README; show the evidence) or **missing** — then ask in one message for what is missing or doubtful. Values the user or `connect` passed to this skill are proposals: echo them back for confirmation. When the harness is already present, the values are `identity` in `.power-platform/project.json`: read them, do not ask again. The artifact language is then read from `openspec/config.yaml`.

- **Publisher.** Prefer the core solution's publisher, then the only custom publisher in the environment. With several candidates, let the user choose. A prefix that matches no publisher is either mistyped or a publisher not created yet: show the existing ones and ask. A default publisher's prefix deserves a warning: projects should own their publisher.
- **Core solution.** Most projects have one; check the proposed name against the environment's list when you have it.

## 3. Existing project: the project's stack wins

Existing project only: `references/existing-project.md`.

## 4. Plan, confirm once, write

List what you will write: each file under `templates/`, at the same relative path in the current folder. A file that already exists is **kept**: it is not overwritten unless the user explicitly accepts overwriting that exact file; the reference file of your mode says what is merged into it instead. `solutions/README.md` and `scripts/README.md` are written for an empty folder only; with `src/PowerPlatform/` from step 6 they lay the workspace out before `dv-connect` runs, so it does not create a root `plugins/` folder, and git keeps the folders because they are not empty.

Ask for the go-ahead **once**, with the resolved values, the file list, the OpenSpec step below and, for an empty folder, the starting code of step 6.

### OpenSpec

Before writing the templates:

- **No `openspec/` yet** — run `openspec init --tools claude,github-copilot,codex --language <artifact language> --no-copilot-cloud --no-animation .` in the current folder. It writes `openspec/` and the `/opsx` skills and commands for Claude Code (`.claude/`), GitHub Copilot (`.github/`) and Codex (`.agents/`), with the `core` profile; never change the profile. The template's `openspec/config.yaml` then replaces the one `init` wrote: it is the one file of this skill that overwrites without asking, because `init` created it a moment ago.
- **`openspec/` exists but `init` never ran** (no `openspec-*` skills under `.claude/skills/`, `.github/skills/` or `.agents/skills/`: an earlier run wrote `config.yaml` without the CLI) — run the `init` above: it keeps the existing `openspec/config.yaml`. `openspec update` does not cover this case: it regenerates only what `init` set up.
- **`openspec/` already exists** — never run `init` over it. Propose `openspec update`, which regenerates the skills and commands for the installed CLI. `openspec/config.yaml` is kept; show as a diff the template's `context` lines it lacks (the index and the artifact language) and add them only when the user accepts.
- **The CLI is missing** (the user declined it in `setup-tools`) — write the templates anyway, `openspec/config.yaml` included, and report `openspec init` as pending, with `setup-tools` to install the CLI.

### Write

For each file:

1. Read the template.
2. Replace every token with its value, and change nothing else: not the wording, not the formatting, not the line endings.
3. Write it.

Afterwards, search the written files for `{{`: no token may survive. If one does, report it as a bug in this harness.

Then, in the written `.power-platform/project.json`, set the `connections` values `connect` resolved and the user confirmed (`dataverse.devUrl`, `dataverse.tenantId`, `repository.url`, `repository.tenantId`); a value it did not resolve stays `null`.

## 5. Reconcile the generated docs

Existing project only: `references/existing-project.md`.

## 6. Starting code

Empty folder only. In an existing project, the standards say when each project is created: the first change that needs it.

First create the folder tree with the script, never by hand: `scripts/new-folders.ps1`, next to this file, run as `powershell -NoProfile -ExecutionPolicy Bypass -File <path to new-folders.ps1> -ProjectName <project name> -PublisherPrefix <prefix> -TargetPath <current folder>` (add `-DryRun` to preview). `-ExecutionPolicy Bypass` is needed because Windows PowerShell refuses unsigned scripts by default; it applies to this one process only. It creates `src/PowerPlatform/Plugins`, `src/PowerPlatform/CustomAPIs` and the WebResources project's `<prefix>_/src/{js,html,css,icons}`, each empty one with a `.gitkeep`, and never overwrites anything. It is the only script in this harness: a folder tree is mechanical and must come out the same every time.

Then create what `docs/development/csharp-plugins.md` and `docs/development/webresources-project.md` — the generated ones, in the current folder — say the first plugin and the first web resource create, and follow them exactly, inside those folders:

- `src/PowerPlatform/PowerPlatform.slnx`, with its solution folders. The `.slnx` format needs the .NET SDK 10 or later: check `dotnet --list-sdks` first.
- `src/PowerPlatform/Plugins/<project name>.Common/`: its `.csproj` and the `PluginBase.cs` taken from `pac plugin init`.
- The WebResources project: the `.esproj`, the three files next to it and its entry in the solution.

No plugin, Custom API, PCF control or test project: each is created with the first change that needs it. Every pin is the latest stable release at its official source at this moment (see "Versions" in `docs/agents/development-standards.md`); say which version you pinned and where you read it.

Then check it: `dotnet build src/PowerPlatform/PowerPlatform.slnx`, and in the WebResources project `npm install`, `npm test` and `npm run lint`. Each must succeed with no errors and no new warnings. A part whose tool is missing (`dotnet` 10 or later, `node` or `pac`, an install the user declined) is not created: report it as pending, with `setup-tools` to install the tool. A check that fails is reported with its output, never left as it is.

## 7. Git

1. **No repository yet** — `git init -b main` (never `master`), then a first commit of the harness files and the starting code.
2. **Existing repository** — the harness files are uncommitted. Offer a commit on a new branch `chore/adopt-power-platform-harness` (`git switch -c`), or `chore/update-power-platform-harness` when the harness was already present, never on a shared branch without asking.

In both cases stage by path only what this skill wrote, merged or created and what `openspec init` or `openspec update` generated; never `git add -A` or `git add .`, which would sweep in the user's own uncommitted work. Show the staged list before committing.

Creating a publisher or a solution is irreversible. Never do it on the user's behalf during this skill.

## 8. Report

State what was written, what was kept, what was reconciled, the template changes applied or declined, the folders the script created, what `openspec init` or `openspec update` did (or that it is pending), the code created with the versions pinned and whether it builds, and what you could not check and why. Then, as a list the user can act on:

1. **Publisher** — if it does not exist in DEV yet, a human creates it with unique name and prefix as resolved.
2. **Core solution** — if it is not `none` and does not exist in DEV yet, a human creates it under that publisher.
3. **Recommended upgrades** — for an existing project, the differences reconciled in step 5, as the team's upgrade backlog.
4. **Workspace trust** — the rules in `.claude/settings.json` that allow the agent's work apply only after each developer accepts Claude Code's trust prompt for the repository; until then every command asks.
5. **Project context** — `docs/context/project.md` has the client, scope and constraints as TBD: the team fills them in, or the first `/opsx:explore`.
6. **Restart the agent** — the `/opsx` commands load on the next start.
7. Work starts with `/opsx:propose`; a quick fix outside OpenSpec reads `docs/agents/development-standards.md` before the first change.
